"""
Minimal HTTP server that mimics the Vercel /api/similarity-check endpoint.

Usage:
    python test_server.py

Then update SimilarityApiService._baseUrl to point to your machine's local IP:
    http://<YOUR_LOCAL_IP>:8080/api/similarity-check

Every POST will be printed to the console so you can verify the app fires
the request automatically after a nearby connection + payload exchange.
"""

import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        print(f"\n{'='*60}")
        print(f"[{datetime.now().isoformat()}] POST {self.path}")
        print(f"Content-Type: {self.headers.get('Content-Type')}")
        try:
            data = json.loads(body)
            print(json.dumps(data, indent=2))
        except Exception:
            print(body.decode(errors="replace"))
        print(f"{'='*60}")

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "ok", "message": "Similarity check queued."}).encode())

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Test server is running. POST to /api/similarity-check\n")


if __name__ == "__main__":
    port = 8080
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"Test server listening on http://0.0.0.0:{port}")
    print(f"Update _baseUrl to: http://<YOUR_LOCAL_IP>:{port}/api/similarity-check")
    print("Waiting for POST requests...\n")
    server.serve_forever()
