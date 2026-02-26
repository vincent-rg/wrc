#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
wrc_server.py - Remote command launcher server (runs inside WSB)

Compatible with: Python 3.9.13+

Usage: python wrc_server.py [port]
  port : Port to listen on (default: 9000)

Endpoints:
  POST /run   { "command": "<cmd>", "workdir": "<path>" }
              Runs the command and streams output line by line.
              workdir is optional; omit to use the server's cwd.
              Each chunk is a JSON line: {"line": "...", "stream": "stdout"|"stderr"}
              Final chunk:              {"exit_code": <int>}

  POST /kill  { "pid": <int> }
              Terminates the process with the given PID.
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

_procs = {}          # pid -> Popen, for /kill
_procs_lock = threading.Lock()


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


def _write_chunk(wfile, data: bytes):
    """Write one HTTP chunked transfer chunk."""
    wfile.write(f'{len(data):X}\r\n'.encode())
    wfile.write(data)
    wfile.write(b'\r\n')
    wfile.flush()


def _write_line(wfile, obj: dict):
    _write_chunk(wfile, (json.dumps(obj, ensure_ascii=False) + '\n').encode('utf-8'))


class CommandHandler(BaseHTTPRequestHandler):
    # HTTP/1.1 is required for Transfer-Encoding: chunked
    protocol_version = 'HTTP/1.1'

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        data = json.loads(self.rfile.read(length))

        if self.path == '/run':
            self._handle_run(data)
        elif self.path == '/kill':
            self._handle_kill(data)
        else:
            self.send_error(404)

    def _handle_run(self, data):
        raw_command = data['command']
        workdir = data.get('workdir') or None

        # Write command to a temp .ps1 file so that 'exit N' propagates to the
        # process exit code.  Using & { } script-block would swallow exit codes.
        # - [Console]::OutputEncoding forces UTF-8 on the pipe
        # - 6>&1 merges Write-Host (stream 6) into stdout
        fd, tmp_path = tempfile.mkstemp(suffix='.ps1')
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as f:
                f.write(raw_command)
        except Exception:
            os.unlink(tmp_path)
            raise

        ps_command = (
            '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; '
            f'& "{tmp_path}" 6>&1'
        )

        print(f'[WRC] Running: {raw_command}' + (f' (cwd={workdir})' if workdir else ''))

        proc = subprocess.Popen(
            ['powershell.exe', '-NoProfile', '-Command', ps_command],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            creationflags=CREATE_NEW_PROCESS_GROUP,
            cwd=workdir,
        )

        with _procs_lock:
            _procs[proc.pid] = proc

        self.send_response(200)
        self.send_header('Content-Type', 'application/x-ndjson')
        self.send_header('Transfer-Encoding', 'chunked')
        self.send_header('Connection', 'close')
        self.send_header('X-WRC-PID', str(proc.pid))
        self.end_headers()

        # Stream stdout and stderr concurrently into the response.
        # Lock ensures the two threads don't interleave chunk writes.
        wfile_lock = threading.Lock()

        def stream(pipe, stream_name):
            try:
                for raw in pipe:
                    line = raw.decode('utf-8', errors='replace').rstrip('\r\n')
                    with wfile_lock:
                        _write_line(self.wfile, {'line': line, 'stream': stream_name})
            except Exception:
                pass

        t_out = threading.Thread(target=stream, args=(proc.stdout, 'stdout'), daemon=True)
        t_err = threading.Thread(target=stream, args=(proc.stderr, 'stderr'), daemon=True)
        t_out.start()
        t_err.start()
        t_out.join()
        t_err.join()

        exit_code = proc.wait()

        try:
            os.unlink(tmp_path)
        except OSError:
            pass

        with _procs_lock:
            _procs.pop(proc.pid, None)

        print(f'[WRC] Done (exit_code={exit_code})')

        _write_line(self.wfile, {'exit_code': exit_code})
        _write_chunk(self.wfile, b'')  # final empty chunk = end of stream

    def _handle_kill(self, data):
        pid = data.get('pid')
        with _procs_lock:
            proc = _procs.get(pid)

        if proc is None:
            body = json.dumps({'error': 'pid not found'}).encode('utf-8')
            self.send_response(404)
        else:
            try:
                proc.terminate()
                status = 'terminated'
            except Exception as e:
                status = f'error: {e}'
            body = json.dumps({'status': status, 'pid': pid}).encode('utf-8')
            self.send_response(200)

        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(body)

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
