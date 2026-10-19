"""Run finite Python + Godot localhost checks; never use official mode or keys."""
import argparse
import json
from pathlib import Path
import subprocess
import threading
import unittest

from server import Engine, LocalServer
from test_server import LocalHTTPTests


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--capture-ui", action="store_true")
    args = parser.parse_args()
    evidence = Path(args.evidence_dir).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    unit = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(LocalHTTPTests))
    if not unit.wasSuccessful():
        return 1
    engine = Engine(mode="stub", max_calls=16, delay=0.25)
    server = LocalServer(0, engine)
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
    thread.start()
    try:
        command = [args.godot, "--headless", "--path", str(Path(args.project_root).resolve()),
                   "--log-file", str(evidence / "godot_loopback_http.log"),
                   "--script", "res://tests/image_generation/verify_loopback_http.gd", "--", "--local-port=%d" % server.server_port]
        process = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20)
        # The test emits only fixed check labels. No session/key/image/prompt is printed.
        print(process.stdout)
        if process.stderr:
            print(process.stderr)
        audit = engine.audit()
        passed = process.returncode == 0 and "LOOPBACK_HTTP_CHECKS: 12 passed / 12 total" in process.stdout
        passed = passed and audit["real_calls"] == 0 and audit["stub_calls"] >= 3 and audit["cache_hits"] >= 1
        ui_checks = None
        if args.capture_ui:
            ui_engine = Engine(mode="stub", max_calls=1, delay=0.25)
            ui_server = LocalServer(0, ui_engine)
            ui_thread = threading.Thread(target=ui_server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
            ui_thread.start()
            try:
                ui_command = [args.godot, "--path", str(Path(args.project_root).resolve()),
                              "res://image_generation/loopback_demo.tscn", "--script", "res://tests/image_generation/verify_loopback_scene.gd",
                              "--log-file", str(evidence / "godot_loopback_scene.log"), "--",
                              "--local-port=%d" % ui_server.server_port, "--evidence-dir=%s" % evidence]
                ui = subprocess.run(ui_command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20)
                print(ui.stdout)
                if ui.stderr: print(ui.stderr)
                ui_checks = ui.returncode == 0 and "LOOPBACK_SCENE_CHECKS: 6 passed / 6 total" in ui.stdout and ui_engine.audit()["stub_calls"] == 1
                passed = passed and ui_checks
            finally:
                ui_server.shutdown()
                ui_server.server_close()
                ui_thread.join(timeout=2)
                ui_engine.close()
        summary = {"python_tests": unit.testsRun, "python_passed": unit.wasSuccessful(),
                   "godot_checks": 12, "passed": passed, "actual_http": True,
                   "mode": "stub", "input": "code-generated bridge and pencil drawing; no boat or personal data",
                   "official_calls": 0, "credential_reads": 0, "audit": audit, "direct_scene_checks_passed": ui_checks}
        (evidence / "loopback_validation.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print("LOCAL_LOOPBACK_ALL_PASSED" if passed else "LOCAL_LOOPBACK_FAILED")
        return 0 if passed else 1
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        engine.close()


if __name__ == "__main__":
    raise SystemExit(main())
