"""Run the recording-flow regression against an isolated loopback STUB. No credential setup."""
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
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--visible", action="store_true", help="Only after the boat task releases its verification window.")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    if args.visible and args.preflight_only:
        parser.error("preflight stays headless; do not request a visible window")
    root = Path(args.project_root).resolve()
    evidence = Path(args.evidence_dir).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    engine = server = thread = None
    command = [args.godot]
    if not args.visible:
        command += ["--headless"]
    command += ["--path", str(root), "--rendering-method", "gl_compatibility", "--max-fps", "15"]
    if args.visible:
        command += ["--resolution", "1920x1080", "--position", "0,0"]
    command += ["--script", "res://tests/levels/verify_recording_flow.gd", "--", "--evidence-dir=" + str(evidence)]
    try:
        if args.preflight_only:
            command += ["--preflight-only"]
        else:
            sys.path.insert(0, str(root / "local_image_service"))
            from server import Engine, LocalServer
            # Fixed STUB mode, fresh ephemeral port, no key or private config reads.
            engine = Engine(mode="stub", max_calls=4, delay=1.0)
            server = LocalServer(0, engine)
            if server.server_port == 8769:
                raise RuntimeError("Refusing reserved production port")
            thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
            thread.start()
            command += ["--local-port=" + str(server.server_port)]
        print("RECORDING_FLOW_START " + ("headless preflight" if args.preflight_only else "single visible app; HTTP STUB only" if args.visible else "headless full flow; HTTP STUB only"), flush=True)
        log_path = evidence / "process.log"
        with log_path.open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            (evidence / "owned_process.json").write_text(json.dumps({"pid": process.pid, "visible": args.visible, "script": "res://tests/levels/verify_recording_flow.gd", "only_child_owned_by_this_runner": True}, indent=2), encoding="utf-8")
            try:
                code = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                # Terminate only the exact child process owned by this runner.
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
                code = -1
        report_path = evidence / "real_flow.json"
        report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else {"status": "failed", "failures": ["missing_report"]}
        audit = engine.audit() if engine is not None else {"mode": "not_started", "stub_calls": 0, "real_calls": 0}
        passed = (not args.preflight_only and code == 0 and report.get("status") == "passed"
                  and not report.get("failures") and audit["mode"] == "stub"
                  and audit["real_calls"] == 0 and 1 <= audit["stub_calls"] <= 2)
        summary = {"status": "passed" if passed else report.get("status", "failed"), "passed": passed,
                   "exit_code": code, "preflight_only": args.preflight_only,
                   "actual_loopback_http": engine is not None, "audit": audit,
                   "credential_reads": 0, "official_model_result_rerun": False,
                   "visible_execution": args.visible, "visible_frame_review": "pending separate inspection" if args.visible else "not executed",
                   "native_mouse_acceptance": False, "flow_report": report_path.name}
        (evidence / "recording_validation.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(summary, ensure_ascii=False), flush=True)
        return 0 if passed else 2 if report.get("status") == "blocked" else 1
    finally:
        if server is not None:
            if thread is not None:
                server.shutdown()
                thread.join(timeout=2)
            server.server_close()
        if engine is not None:
            engine.close()


if __name__ == "__main__":
    raise SystemExit(main())
