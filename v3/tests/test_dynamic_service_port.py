from __future__ import annotations

import unittest
from unittest.mock import Mock

from research_os_v3.service import V3LocalService


class DynamicV3ServicePortTests(unittest.TestCase):
    def test_port_zero_is_replaced_with_the_actual_bound_socket_port(self) -> None:
        layout = Mock()
        layout.ensure.return_value = layout
        service = V3LocalService(host="127.0.0.1", port=0, data_layout=layout)
        server = service.build_server()
        try:
            actual_port = int(server.server_address[1])
            self.assertGreater(actual_port, 0)
            self.assertEqual(service.port, actual_port)
        finally:
            server.server_close()
            service._server = None


if __name__ == "__main__":
    unittest.main()
