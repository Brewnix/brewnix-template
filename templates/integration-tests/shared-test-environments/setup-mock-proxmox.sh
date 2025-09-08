#!/bin/bash

# BrewNix Mock Proxmox Environment Setup
# Phase 2.1.2 - Cross-Submodule Integration Testing
#
# This script sets up a mock Proxmox VE environment for integration testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
MOCK_PROXMOX_PORT=${MOCK_PROXMOX_PORT:-8080}
MOCK_DATA_FILE="${SCRIPT_DIR}/mock-data/mock-proxmox-data.json"
CONTAINER_NAME="brewnix-mock-proxmox"
IMAGE_NAME="brewnix/mock-proxmox:latest"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[MOCK-PROXMOX]${NC} $1"
}

log_error() {
    echo -e "${RED}[MOCK-PROXMOX]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[MOCK-PROXMOX]${NC} $1"
}

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi

    log_info "Docker is available and running"
    return 0
}

# Create mock data directory
create_mock_data() {
    local mock_data_dir="${SCRIPT_DIR}/mock-data"
    mkdir -p "$mock_data_dir"

    if [ ! -f "$MOCK_DATA_FILE" ]; then
        log_info "Creating mock Proxmox data file..."

        cat > "$MOCK_DATA_FILE" << 'EOF'
{
  "version": {
    "version": "8.1-1",
    "release": "8.1",
    "repoid": "main"
  },
  "nodes": [
    {
      "id": "node1",
      "name": "proxmox-node-01",
      "type": "node",
      "status": "online",
      "cpu": 0.15,
      "memory": {
        "used": 2147483648,
        "total": 8589934592
      },
      "storage": {
        "used": 10737418240,
        "total": 53687091200
      }
    }
  ],
  "pools": [
    {
      "poolid": "test-pool",
      "comment": "Test pool for integration testing"
    }
  ],
  "storage": [
    {
      "id": "local",
      "type": "dir",
      "content": "iso,vztmpl,backup",
      "enabled": 1,
      "shared": 0,
      "used": 10737418240,
      "total": 53687091200
    },
    {
      "id": "local-lvm",
      "type": "lvmthin",
      "content": "rootdir,images",
      "enabled": 1,
      "shared": 0,
      "used": 5368709120,
      "total": 107374182400
    }
  ],
  "vms": [
    {
      "vmid": 100,
      "name": "test-vm-01",
      "status": "stopped",
      "cpus": 2,
      "memory": 2048,
      "disk": 32,
      "node": "proxmox-node-01"
    },
    {
      "vmid": 101,
      "name": "test-vm-02",
      "status": "running",
      "cpus": 4,
      "memory": 4096,
      "disk": 64,
      "node": "proxmox-node-01"
    }
  ],
  "lxc": [
    {
      "vmid": 200,
      "name": "test-lxc-01",
      "status": "running",
      "cpus": 1,
      "memory": 1024,
      "disk": 16,
      "node": "proxmox-node-01"
    }
  ]
}
EOF

        log_info "Mock Proxmox data file created: $MOCK_DATA_FILE"
    else
        log_info "Mock Proxmox data file already exists: $MOCK_DATA_FILE"
    fi
}

# Build mock Proxmox Docker image
build_mock_image() {
    log_info "Building mock Proxmox Docker image..."

    local dockerfile_path="${SCRIPT_DIR}/Dockerfile"

    if [ ! -f "$dockerfile_path" ]; then
        log_info "Creating Dockerfile for mock Proxmox..."

        cat > "$dockerfile_path" << 'EOF'
FROM python:3.9-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy mock data
COPY mock-data/mock-proxmox-data.json /app/mock-data/

# Copy mock server script
COPY mock-server.py /app/

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/api2/json/version || exit 1

# Start mock server
CMD ["python", "mock-server.py"]
EOF

        log_info "Dockerfile created: $dockerfile_path"
    fi

    # Build the image
    docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"
    log_info "Mock Proxmox image built successfully: $IMAGE_NAME"
}

# Create mock server script
create_mock_server() {
    local mock_server_path="${SCRIPT_DIR}/mock-server.py"

    if [ ! -f "$mock_server_path" ]; then
        log_info "Creating mock Proxmox server script..."

        cat > "$mock_server_path" << 'EOF'
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
EOF

        chmod +x "$mock_server_path"
        log_info "Mock server script created: $mock_server_path"
    fi
}

# Start mock Proxmox container
start_mock_container() {
    log_info "Starting mock Proxmox container..."

    # Stop any existing container
    if docker ps -a --format 'table {{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warning "Stopping existing mock Proxmox container..."
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi

    # Start new container
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "${MOCK_PROXMOX_PORT}:8080" \
        -v "${SCRIPT_DIR}/mock-data:/app/mock-data:ro" \
        -e MOCK_PROXMOX_PORT=8080 \
        "$IMAGE_NAME"

    log_info "Mock Proxmox container started: $CONTAINER_NAME"
    log_info "Mock API available at: http://localhost:${MOCK_PROXMOX_PORT}/api2/json/"
}

# Wait for mock service to be ready
wait_for_service() {
    log_info "Waiting for mock Proxmox service to be ready..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -f -s "http://localhost:${MOCK_PROXMOX_PORT}/api2/json/version" >/dev/null 2>&1; then
            log_info "Mock Proxmox service is ready!"
            return 0
        fi

        log_info "Waiting for service... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    log_error "Mock Proxmox service failed to start within ${max_attempts} attempts"
    return 1
}

# Main execution
main() {
    log_info "Setting up mock Proxmox environment for integration testing..."

    # Check prerequisites
    check_docker || exit 1

    # Create mock data
    create_mock_data

    # Create mock server
    create_mock_server

    # Build Docker image
    build_mock_image

    # Start container
    start_mock_container

    # Wait for service readiness
    wait_for_service || exit 1

    log_info "Mock Proxmox environment setup completed successfully!"
    log_info "Service Details:"
    log_info "  - Container: $CONTAINER_NAME"
    log_info "  - API URL: http://localhost:${MOCK_PROXMOX_PORT}/api2/json/"
    log_info "  - Status: Running"
}

# Execute main function
main "$@"
