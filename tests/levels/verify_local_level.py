"""Finite level -> real drawing export -> actual loopback HTTP STUB checks only."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import threading


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--headless", action="store_true", help="Run protocol checks without desktop windows or screenshot capture.")
    args = parser.parse_args()
    root = Path(args.project_root).resolve()
    evidence = Path(args.evidence_dir).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(root / "local_image_service"))
    from server import Engine, LocalServer

    # No official engine, getpass, credential lookup or fixed production port.
    engine = Engine(mode="stub", max_calls=4, delay=0.35)
    server = LocalServer(0, engine)
    if server.server_port == 8769:
        server.server_close()
        engine.close()
        raise RuntimeError("Refusing reserved production port")
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
    thread.start()
    results = {}
    try:
        for test_case in ["idle", "official_idle", "flow"]:
            selected_mode = "official" if test_case == "official_idle" else "stub"
            command = [args.godot] + (["--headless"] if args.headless else []) + ["--path", str(root), "--scene", "res://tests/levels/verify_local_level.tscn",
                       "--quit-after", "1800", "--", "--local-mode=" + selected_mode, "--local-port=%d" % server.server_port,
                       "--case=" + test_case, "--evidence-dir=" + str(evidence)]
            completed = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=35)
            text = completed.stdout + completed.stderr
            (evidence / (test_case + ".log")).write_text(text, encoding="utf-8")
            print(text)
            report_path = evidence / (test_case + "_checks.json")
            report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else {"failures": ["missing_report"]}
            report["exit_code"] = completed.returncode
            report["audit"] = engine.audit()
            results[test_case] = report
            if completed.returncode or report["failures"]:
                break
        idle = results.get("idle", {})
        official_idle = results.get("official_idle", {})
        flow = results.get("flow", {})
        passed = (not idle.get("failures", [True]) and idle.get("audit", {}).get("stub_calls") == 0
                  and not official_idle.get("failures", [True]) and official_idle.get("audit", {}).get("stub_calls") == 0
                  and not flow.get("failures", [True]) and flow.get("audit", {}).get("stub_calls", 0) >= 1
                  and engine.audit()["real_calls"] == 0)
        summary = {"passed": passed, "cases": results, "actual_loopback_http": True,
                   "server_mode": "stub", "official_calls": 0, "credential_reads": 0,
                   "opens_panel_without_send_verified": idle.get("audit", {}).get("stub_calls") == 0 and official_idle.get("audit", {}).get("stub_calls") == 0}
        (evidence / "validation.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print("LEVEL_LOCAL_HTTP_PASSED" if passed else "LEVEL_LOCAL_HTTP_FAILED")
        return 0 if passed else 1
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        engine.close()


if __name__ == "__main__":
    raise SystemExit(main())
