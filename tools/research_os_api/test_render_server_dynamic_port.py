from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "research_os_api" / "render_server.py"


@unittest.skipIf(os.name == "nt", "SIGINT process lifecycle test is exercised on Linux CI")
class RenderServerDynamicPortTests(unittest.TestCase):
    def test_server_binds_and_publishes_the_actual_os_assigned_port(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            data_dir = Path(temporary)
            registry_dir = data_dir / "run" / "services"
            env = os.environ.copy()
            env.update({
                "RESEARCH_OS_DATA_DIR": str(data_dir),
                "RESEARCH_OS_SERVICE_REGISTRY_DIR": str(registry_dir),
                "RESEARCH_OS_API_HOST": "127.0.0.1",
                "RESEARCH_OS_API_PORT": "0",
                "HOST": "127.0.0.1",
                "PORT": "0",
                "PYTHONUNBUFFERED": "1",
            })
            process = subprocess.Popen(
                [sys.executable, str(SCRIPT)],
                cwd=str(SCRIPT.parent),
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            endpoint_file = registry_dir / "research-os-api.json"
            try:
                deadline = time.monotonic() + 20
                endpoint = None
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        stdout, stderr = process.communicate(timeout=2)
                        self.fail(f"API exited before publishing endpoint. stdout={stdout} stderr={stderr}")
                    if endpoint_file.is_file():
                        try:
                            endpoint = json.loads(endpoint_file.read_text(encoding="utf-8"))
                            break
                        except (OSError, json.JSONDecodeError):
                            pass
                    time.sleep(0.1)

                self.assertIsNotNone(endpoint, "API did not publish an endpoint")
                self.assertEqual(endpoint["service"], "research-os-api")
                self.assertEqual(endpoint["host"], "127.0.0.1")
                self.assertGreater(endpoint["port"], 0)
                self.assertEqual(endpoint["base_url"], f"http://127.0.0.1:{endpoint['port']}")

                with urllib.request.urlopen(endpoint["base_url"] + "/health", timeout=3) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                    self.assertEqual(response.status, 200)
                    self.assertEqual(payload.get("status"), "ok")

                process.send_signal(signal.SIGINT)
                process.wait(timeout=10)
                self.assertFalse(endpoint_file.exists(), "API shutdown must remove its own registry record")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
