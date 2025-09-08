#!/usr/bin/env python3

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse

class MockProxmoxHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        # Load mock data
        mock_data_file = os.path.join(os.path.dirname(__file__), 'mock-data', 'mock-proxmox-data.json')
        with open(mock_data_file, 'r') as f:
            self.mock_data = json.load(f)
        super().__init__(*args, **kwargs)

    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)
        path_parts = parsed_path.path.strip('/').split('/')

        # Set CORS headers
        self.send_cors_headers()

        # Route requests
        if parsed_path.path == '/api2/json/version':
            self.send_json_response(self.mock_data['version'])
        elif parsed_path.path == '/api2/json/nodes':
            self.send_json_response({'data': self.mock_data['nodes']})
        elif parsed_path.path == '/api2/json/pools':
            self.send_json_response({'data': self.mock_data['pools']})
        elif parsed_path.path == '/api2/json/storage':
            self.send_json_response({'data': self.mock_data['storage']})
        elif parsed_path.path.startswith('/api2/json/nodes/') and parsed_path.path.endswith('/qemu'):
            # Mock VM list for a node
            node_name = path_parts[3] if len(path_parts) > 3 else 'node1'
            vms = [vm for vm in self.mock_data['vms'] if vm['node'] == f'proxmox-{node_name}']
            self.send_json_response({'data': vms})
        elif parsed_path.path.startswith('/api2/json/nodes/') and parsed_path.path.endswith('/lxc'):
            # Mock LXC container list for a node
            node_name = path_parts[3] if len(path_parts) > 3 else 'node1'
            lxc = [container for container in self.mock_data['lxc'] if container['node'] == f'proxmox-{node_name}']
            self.send_json_response({'data': lxc})
        else:
            self.send_error(404, "Endpoint not found")

    def send_cors_headers(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')

    def send_json_response(self, data):
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, format, *args):
        # Suppress default logging
        pass

def run_server(port):
    server_address = ('', port)
    httpd = HTTPServer(server_address, MockProxmoxHandler)
    print(f"Mock Proxmox server running on port {port}")
    httpd.serve_forever()

if __name__ == '__main__':
    port = int(os.environ.get('MOCK_PROXMOX_PORT', 8080))
    run_server(port)
