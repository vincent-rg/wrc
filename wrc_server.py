#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
wrc_server.py - Remote command launcher server (runs inside WSB)

Compatible with: Python 3.9.13+

Usage: python wrc_server.py [port]
  port : Port to listen on (default: 9000)
"""

import json
import socket
import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

CREATE_NEW_CONSOLE = 0x00000010


def get_outbound_ip():
    """Return the IP of the interface used to reach the outside network."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))  # no packet sent, just sets routing
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return socket.gethostbyname(socket.gethostname())


class CommandHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        data = json.loads(self.rfile.read(length))
        command = data['command']

        print(f'[WRC] Running: {command}')

        proc = subprocess.Popen(command, shell=True, creationflags=CREATE_NEW_CONSOLE)
        exit_code = proc.wait()

        print(f'[WRC] Done (exit_code={exit_code})')

        body = json.dumps({'exit_code': exit_code}).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass  # suppress default HTTP access log


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9000
    ip = get_outbound_ip()
    server = HTTPServer(('0.0.0.0', port), CommandHandler)
    print(f'[WRC] Listening on {ip}:{port}')
    server.serve_forever()


if __name__ == '__main__':
    main()
