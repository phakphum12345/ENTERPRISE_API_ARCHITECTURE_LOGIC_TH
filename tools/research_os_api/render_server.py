#!/usr/bin/env python3
"""Cloud and local entrypoint for Research OS API with browser-safe CORS headers."""

from __future__ import annotations

import os
from http import HTTPStatus
from http.server import ThreadingHTTPServer

from service_registry import publish_endpoint, registry_directory, remove_endpoint
from v2_server import V2ResearchOSHandler


class CloudResearchOSHandler(V2ResearchOSHandler):
    """Primary Research OS handler with V1 compatibility and V2 namespace."""

    def end_headers(self) -> None:
        configured_origins = os.getenv(
            "RESEARCH_OS_ALLOWED_ORIGINS",
            "https://phakphum12345.github.io,https://phakphoum38-stack.github.io",
        )
        allowed_origins = {item.strip() for item in configured_origins.split(",") if item.strip()}
        request_origin = (self.headers.get("Origin") or "").strip()
        if request_origin in allowed_origins:
            self.send_header("Access-Control-Allow-Origin", request_origin)
        self.send_header("Vary", "Origin")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, Authorization, X-Research-OS-Sync-Key, X-Research-OS-Session, X-Research-OS-OAuth-State",
        )
        self.send_header("Access-Control-Max-Age", "86400")
        super().end_headers()

    def do_HEAD(self) -> None:  # noqa: N802
        """Serve lightweight HEAD probes without emitting a response body."""
        if self.path.split("?", 1)[0] in {"/", "/health", "/health/"}:
            self.send_response(HTTPStatus.OK)
        else:
            self.send_response(HTTPStatus.NOT_FOUND)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.end_headers()


def main() -> int:
    # Hosted deployments supply PORT. Local launchers default to 0 so the OS
    # atomically assigns a free port during the actual listen() call.
    hosted_port = os.getenv("PORT")
    if hosted_port:
        # PaaS deployments must bind the platform-provided interface and port.
        host = os.getenv("HOST") or os.getenv("RESEARCH_OS_API_HOST") or "0.0.0.0"
    else:
        host = os.getenv("RESEARCH_OS_API_HOST") or "127.0.0.1"
    port_value = hosted_port or os.getenv("RESEARCH_OS_API_PORT") or "0"
    port = int(port_value)
    server = ThreadingHTTPServer((host, port), CloudResearchOSHandler)
    actual_host, actual_port = server.server_address[:2]
    registry_path = registry_directory()
    published = False
    if actual_host in {"127.0.0.1", "::1", "localhost"}:
        endpoint = publish_endpoint(
            "research-os-api",
            str(actual_host),
            int(actual_port),
            directory=registry_path,
        )
        published = True
        print(
            f"Research OS API READY {endpoint['base_url']} registry={registry_path}",
            flush=True,
        )
    else:
        print(
            f"Research OS API listening on {actual_host}:{actual_port}",
            flush=True,
        )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        if published:
            remove_endpoint(
                "research-os-api",
                directory=registry_path,
                pid=os.getpid(),
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
