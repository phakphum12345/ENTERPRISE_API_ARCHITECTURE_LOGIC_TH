from __future__ import annotations

import json
import tempfile
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path

from service_registry import publish_endpoint, read_endpoint, remove_endpoint


class ServiceRegistryTests(unittest.TestCase):
    def test_publishes_the_actual_port_bound_by_the_os(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            server = ThreadingHTTPServer(("127.0.0.1", 0), lambda *_: None)
            try:
                actual_port = int(server.server_address[1])
                self.assertGreater(actual_port, 0)
                published = publish_endpoint(
                    "research-os-api", "127.0.0.1", actual_port,
                    directory=directory, pid=1234,
                )
                self.assertEqual(published["port"], actual_port)
                self.assertEqual(read_endpoint("research-os-api", directory=directory), published)
                self.assertEqual(
                    json.loads((directory / "research-os-api.json").read_text())["base_url"],
                    f"http://127.0.0.1:{actual_port}",
                )
            finally:
                server.server_close()

    def test_refuses_unassigned_or_non_loopback_endpoints(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with self.assertRaises(ValueError):
                publish_endpoint("research-os-api", "127.0.0.1", 0, directory=directory)
            with self.assertRaises(ValueError):
                publish_endpoint("research-os-api", "0.0.0.0", 43123, directory=directory)
            self.assertFalse((directory / "research-os-api.json").exists())

    def test_remove_is_guarded_by_process_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            publish_endpoint("owner-friend", "127.0.0.1", 43123, directory=directory, pid=77)
            self.assertFalse(remove_endpoint("owner-friend", directory=directory, pid=78))
            self.assertIsNotNone(read_endpoint("owner-friend", directory=directory))
            self.assertTrue(remove_endpoint("owner-friend", directory=directory, pid=77))
            self.assertIsNone(read_endpoint("owner-friend", directory=directory))

    def test_invalid_service_identifier_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError):
                read_endpoint("../api", directory=Path(temporary))


if __name__ == "__main__":
    unittest.main()
