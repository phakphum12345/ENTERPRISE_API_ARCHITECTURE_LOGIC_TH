"""Research OS example application entrypoint."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import os


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":"ok","name":"research-os"}')


def run(server_class=HTTPServer, handler_class=Handler):
    port = int(os.environ.get("RESEARCH_OS_PORT", "8080"))
    server_address = ("", port)
    httpd = server_class(server_address, handler_class)
    print(f"Research OS running on port {port}")
    httpd.serve_forever()


if __name__ == "__main__":
    run()
