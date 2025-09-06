#!/usr/bin/env python3
"""
Brewnix Web UI
GitOps-driven management interface for all Brewnix server deployments
"""

import os
import yaml
import json
import subprocess
from datetime import datetime
from flask import Flask, render_template, request, jsonify, flash, redirect, url_for
from pathlib import Path

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key')

# Configuration
CONFIG_DIR = Path('/opt/brewnix/config/sites')
DEVICE_DIR = Path('/opt/brewnix/config/devices')
BOOTSTRAP_DIR = Path('/opt/brewnix/bootstrap')
REPO_DIR = Path('/opt/brewnix')

@app.route('/')
def dashboard():
    """Main dashboard showing all systems status"""
    try:
        # Get system information for all sites
        sites = get_all_sites()
        devices = get_all_devices()
        system_status = get_overall_status()

        return render_template('dashboard.html',
                             sites=sites,
                             devices=devices,
                             system_status=system_status)
    except Exception as e:
        return render_template('error.html', error=str(e))

@app.route('/sites')
def sites():
    """Site configuration management"""
    sites = []
    if CONFIG_DIR.exists():
        for config_file in CONFIG_DIR.glob('*.yml'):
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
                config['filename'] = config_file.name
                config['type'] = config.get('server_type', 'unknown')
                sites.append(config)

    return render_template('sites.html', sites=sites)

@app.route('/sites/new', methods=['GET', 'POST'])
def new_site():
    """Create new site configuration"""
    if request.method == 'POST':
        server_type = request.form['server_type']
        site_config = {
            'site_name': request.form['site_name'],
            'server_type': server_type,
            'location': request.form.get('location', ''),
            'admin_email': request.form.get('admin_email', ''),
            'network': {
                'vlan_id': int(request.form.get('vlan_id', 20)),
                'ip_range': request.form.get('ip_range', '192.168.1.0/24')
            }
        }

        # Add server-type specific configuration
        if server_type == 'proxmox-nas':
            site_config.update({
                'storage': {
                    'system_disks': request.form.getlist('system_disks'),
                    'data_disks': request.form.getlist('data_disks'),
                    'raid_level': request.form.get('raid_level', 'raidz1')
                },
                'proxmox': {
                    'api_host': request.form.get('api_host', 'localhost'),
                    'api_user': request.form.get('api_user', 'root@pam')
                }
            })
        elif server_type == 'proxmox-firewall':
            site_config.update({
                'firewall': {
                    'interfaces': request.form.getlist('interfaces'),
                    'rules': request.form.get('rules', [])
                }
            })
        elif server_type == 'k3s-cluster':
            site_config.update({
                'kubernetes': {
                    'nodes': int(request.form.get('nodes', 3)),
                    'version': request.form.get('k8s_version', 'v1.28.0')
                }
            })

        # Save configuration
        config_file = CONFIG_DIR / f"{request.form['site_name']}.yml"
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)

        with open(config_file, 'w') as f:
            yaml.dump(site_config, f, default_flow_style=False)

        flash(f'{server_type.upper()} site configuration created successfully!')
        return redirect(url_for('sites'))

    return render_template('site_form.html')

@app.route('/devices')
def devices():
    """Device registration management"""
    devices = get_all_devices()
    return render_template('devices.html', devices=devices)

@app.route('/devices/register', methods=['GET', 'POST'])
def register_device():
    """Register a new device"""
    if request.method == 'POST':
        device_config = {
            'device_id': request.form['device_id'],
            'device_type': request.form['device_type'],
            'site_name': request.form['site_name'],
            'ip_address': request.form.get('ip_address'),
            'mac_address': request.form.get('mac_address'),
            'serial_number': request.form.get('serial_number'),
            'registered_at': datetime.now().isoformat(),
            'status': 'registered'
        }

        # Save device configuration
        device_file = DEVICE_DIR / f"{request.form['device_id']}.yml"
        DEVICE_DIR.mkdir(parents=True, exist_ok=True)

        with open(device_file, 'w') as f:
            yaml.dump(device_config, f, default_flow_style=False)

        flash('Device registered successfully!')
        return redirect(url_for('devices'))

    # Get available sites for dropdown
    sites = []
    if CONFIG_DIR.exists():
        for config_file in CONFIG_DIR.glob('*.yml'):
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
                sites.append(config['site_name'])

    return render_template('device_form.html', sites=sites)

@app.route('/bootstrap/<site_name>', methods=['POST'])
def create_bootstrap(site_name):
    """Generate bootstrap media for a site"""
    try:
        config_file = CONFIG_DIR / f"{site_name}.yml"
        if not config_file.exists():
            flash(f'Site configuration not found: {site_name}', 'error')
            return redirect(url_for('sites'))

        usb_device = request.form.get('usb_device')
        if not usb_device:
            flash('USB device not specified', 'error')
            return redirect(url_for('sites'))

        # Run bootstrap creation script
        result = subprocess.run([
            '/opt/brewnix/bootstrap/create-bootstrap.sh',
            '--site-config', str(config_file),
            '--usb-device', usb_device
        ], capture_output=True, text=True, cwd='/opt/brewnix')

        if result.returncode == 0:
            flash(f'Bootstrap media created successfully for {site_name}!')
        else:
            flash(f'Error creating bootstrap: {result.stderr}', 'error')

    except Exception as e:
        flash(f'Error: {str(e)}', 'error')

    return redirect(url_for('sites'))

@app.route('/deploy/<site_name>', methods=['POST'])
def deploy_site(site_name):
    """Trigger deployment for a specific site"""
    try:
        config_file = CONFIG_DIR / f"{site_name}.yml"
        if not config_file.exists():
            flash(f'Site configuration not found: {site_name}', 'error')
            return redirect(url_for('sites'))

        # Load site config to determine server type
        with open(config_file, 'r') as f:
            site_config = yaml.safe_load(f)

        server_type = site_config.get('server_type', 'unknown')

        # Run appropriate deployment playbook
        playbook_path = f'/opt/brewnix/vendor/{server_type.replace("-", "_")}/ansible/site.yml'

        result = subprocess.run([
            'ansible-playbook',
            playbook_path,
            '-e', f'site_config_file={config_file}'
        ], capture_output=True, text=True, cwd='/opt/brewnix')

        if result.returncode == 0:
            flash(f'Deployment completed successfully for {site_name}!')
        else:
            flash(f'Deployment failed: {result.stderr}', 'error')

    except Exception as e:
        flash(f'Error: {str(e)}', 'error')

    return redirect(url_for('sites'))

@app.route('/api/sites')
def api_sites():
    """API endpoint for site information"""
    return jsonify(get_all_sites())

@app.route('/api/devices')
def api_devices():
    """API endpoint for device information"""
    return jsonify(get_all_devices())

@app.route('/api/status')
def api_status():
    """API endpoint for overall system status"""
    return jsonify(get_overall_status())

def get_all_sites():
    """Get all site configurations"""
    sites = []
    if CONFIG_DIR.exists():
        for config_file in CONFIG_DIR.glob('*.yml'):
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
                config['filename'] = config_file.name
                sites.append(config)
    return sites

def get_all_devices():
    """Get all device registrations"""
    devices = []
    if DEVICE_DIR.exists():
        for device_file in DEVICE_DIR.glob('*.yml'):
            with open(device_file, 'r') as f:
                device = yaml.safe_load(f)
                device['filename'] = device_file.name
                devices.append(device)
    return devices

def get_overall_status():
    """Get overall system status"""
    try:
        sites = get_all_sites()
        devices = get_all_devices()

        return {
            'total_sites': len(sites),
            'total_devices': len(devices),
            'server_types': list(set(site.get('server_type', 'unknown') for site in sites)),
            'timestamp': datetime.now().isoformat()
        }
    except Exception as e:
        return {'error': str(e)}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
