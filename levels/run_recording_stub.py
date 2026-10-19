"""Open the ordinary level for manual play/recording with an isolated, non-AI STUB."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot 4.7.2 executable")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(root / "local_image_service"))
    from server import Engine, LocalServer
    directory = Path(tempfile.mkdtemp(prefix="boat-recording-stub-"))
    engine = Engine(mode="stub", max_calls=8)
    server = LocalServer(0, engine)
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval":0.05}, daemon=True)
    thread.start()
    print("Manual level entry with isolated HTTP STUB (not AI). No official model rerun. Log: " + str(directory), flush=True)
    try:
        with (directory / "godot.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen([args.godot, "--path", str(root), "--rendering-method", "gl_compatibility",
                                        "--max-fps", "30", "--scene", "res://levels/integrated_demo.tscn", "--",
                                        "--local-mode=stub", "--local-port="+str(server.server_port)],
                                       stdout=log, stderr=subprocess.STDOUT,
                                       creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0))
            code = process.wait()  # User owns the visible window; no test timeout or scripted input.
        audit = engine.audit()
        (directory / "stub_audit.json").write_text(json.dumps({"audit":audit,"official_model_result_rerun":False,"credential_reads":0},indent=2),encoding="utf-8")
        return code
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        engine.close()


if __name__ == "__main__":
    raise SystemExit(main())
