#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
wrc_server.py - Remote command launcher server (runs inside WSB)

Compatible with: Python 3.9.13+

Usage: python wrc_server.py [port]
  port : Port to listen on (default: 9000)

Endpoints:
  POST /run   { "command": "<cmd>", "workdir": "<path>" }
              Runs the command; output appears on the server console.
              workdir is optional; omit to use the server's cwd.
              Response: {"exit_code": <int>}
"""

import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

# Isolate child from the server's Ctrl+C console event
CREATE_NEW_PROCESS_GROUP = 0x00000200


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


def _json_response(handler, status, obj):
    body = json.dumps(obj, ensure_ascii=False).encode('utf-8')
    handler.send_response(status)
    handler.send_header('Content-Type', 'application/json')
    handler.send_header('Content-Length', str(len(body)))
    handler.send_header('Connection', 'close')
    handler.end_headers()
    handler.wfile.write(body)


class CommandHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        data = json.loads(self.rfile.read(length))

        if self.path == '/run':
            self._handle_run(data)
        else:
            self.send_error(404)

    def _handle_run(self, data):
        raw_command = data['command']
        workdir = data.get('workdir') or None

        # Write command to a temp .ps1 file so that 'exit N' propagates to the
        # process exit code.  Using & { } script-block would swallow exit codes.
        fd, tmp_path = tempfile.mkstemp(suffix='.ps1')
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as f:
                f.write(raw_command)
        except Exception:
            os.unlink(tmp_path)
            raise

        print(f'[WRC] Running: {raw_command}' + (f' (cwd={workdir})' if workdir else ''))

        proc = subprocess.Popen(
            ['powershell.exe', '-NoProfile', '-File', tmp_path],
            creationflags=CREATE_NEW_PROCESS_GROUP,
            cwd=workdir,
        )

        exit_code = proc.wait()

        try:
            os.unlink(tmp_path)
        except OSError:
            pass

        print(f'[WRC] Done (exit_code={exit_code})')
        _json_response(self, 200, {'exit_code': exit_code})

    def log_message(self, format, *args):
        pass  # suppress default HTTP access log


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9000
    ip = get_outbound_ip()
    server = ThreadingHTTPServer(('0.0.0.0', port), CommandHandler)
    print(f'[WRC] Listening on {ip}:{port}')
    server.serve_forever()


if __name__ == '__main__':
    main()
