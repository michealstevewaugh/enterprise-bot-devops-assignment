import json
import os
def get_config(key, default):
    path = f"/etc/demo-config/{key}"
    try:
        with open(path, "r", encoding="utf-8") as file:
            return file.read().strip()
    except FileNotFoundError:
        return os.getenv(key, default)
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):

    def do_GET(self):
        if self.path == "/":
            response = {
                "app": get_config("APP_NAME", "demo-app"),
                "version": get_config("VERSION", "1.0.0"),
                "pod": os.getenv("HOSTNAME", os.uname().nodename),
            }
            self.send_json(200, response)

        elif self.path == "/healthz":
            self.send_json(200, {"status": "healthy"})

        else:
            self.send_json(404, {"error": "not found"})

    def send_json(self, status, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8080), Handler)
    print("Server listening on port 8080", flush=True)
    server.serve_forever()
