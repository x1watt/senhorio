#!/usr/bin/env python3
"""Serves build/web (the browser preview) with the MIME types wasm needs.
Usage: tool/serve_web.py [port]   (default 8080)"""
import http.server
import os
import socketserver
import sys

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'web'))


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        '.wasm': 'application/wasm',
        '.mjs': 'text/javascript',
        '.js': 'text/javascript',
        '.json': 'application/json',
    }

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()


socketserver.ThreadingTCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(('0.0.0.0', port), Handler) as httpd:
    print(f'Senhorio preview on http://0.0.0.0:{port}/', flush=True)
    httpd.serve_forever()
