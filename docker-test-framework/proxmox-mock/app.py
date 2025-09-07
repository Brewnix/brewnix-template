#!/usr/bin/env python3
"""
Proxmox VE Mock API Server
Provides realistic Proxmox API responses for testing
"""

import os
import json
from flask import Flask, jsonify, request
from flask_cors import CORS
from mock_data import MockDataProvider

app = Flask(__name__)
CORS(app)

# Initialize mock data provider
mock_data = MockDataProvider()

@app.route('/api2/json/version', methods=['GET'])
def get_version():
    """Get Proxmox VE version information"""
    return jsonify({
        "data": {
            "version": "8.0.4",
            "release": "1",
            "repoid": "d258449d"
        }
    })

@app.route('/api2/json/nodes', methods=['GET'])
def get_nodes():
    """Get list of cluster nodes"""
    return jsonify({
        "data": mock_data.get_nodes()
    })

@app.route('/api2/json/nodes/<node>/status', methods=['GET'])
def get_node_status(node):
    """Get node status information"""
    return jsonify({
        "data": mock_data.get_node_status(node)
    })

@app.route('/api2/json/nodes/<node>/storage', methods=['GET'])
def get_node_storage(node):
    """Get storage information for a node"""
    return jsonify({
        "data": mock_data.get_storage(node)
    })

@app.route('/api2/json/nodes/<node>/qemu', methods=['GET'])
def get_node_vms(node):
    """Get VMs on a node"""
    return jsonify({
        "data": mock_data.get_vms(node)
    })

@app.route('/api2/json/nodes/<node>/lxc', methods=['GET'])
def get_node_containers(node):
    """Get containers on a node"""
    return jsonify({
        "data": mock_data.get_containers(node)
    })

@app.route('/api2/json/nodes/<node>/network', methods=['GET'])
def get_node_network(node):
    """Get network configuration for a node"""
    return jsonify({
        "data": mock_data.get_network_config(node)
    })

@app.route('/api2/json/pools', methods=['GET'])
def get_pools():
    """Get resource pools"""
    return jsonify({
        "data": mock_data.get_pools()
    })

@app.route('/api2/json/cluster/status', methods=['GET'])
def get_cluster_status():
    """Get cluster status"""
    return jsonify({
        "data": mock_data.get_cluster_status()
    })

@app.route('/api2/json/access/users', methods=['GET'])
def get_users():
    """Get users"""
    return jsonify({
        "data": mock_data.get_users()
    })

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "service": "proxmox-mock",
        "timestamp": mock_data.get_current_time()
    })

@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors"""
    return jsonify({
        "errors": [f"Path not found: {request.path}"]
    }), 404

@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors"""
    return jsonify({
        "errors": ["Internal server error"]
    }), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8006))
    debug = os.environ.get('DEBUG', 'false').lower() == 'true'
    
    print(f"Starting Proxmox Mock API server on port {port}")
    print(f"Debug mode: {debug}")
    
    app.run(
        host='0.0.0.0', 
        port=port, 
        debug=debug
    )
