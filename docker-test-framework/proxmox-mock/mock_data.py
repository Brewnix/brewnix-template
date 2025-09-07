#!/usr/bin/env python3
"""
Mock data provider for Proxmox VE API
Generates realistic test data for all API endpoints
"""

import time
import random
from datetime import datetime
from typing import Dict, List, Any


class MockDataProvider:
    """Provides mock data for Proxmox VE API endpoints"""
    
    def __init__(self):
        self.start_time = time.time()
        self.nodes = ["pve1", "pve2", "pve3"]
        
    def get_current_time(self) -> float:
        """Get current timestamp"""
        return time.time()
        
    def get_uptime(self) -> int:
        """Get mock uptime in seconds"""
        return int(time.time() - self.start_time)
        
    def get_nodes(self) -> List[Dict[str, Any]]:
        """Get list of cluster nodes"""
        nodes = []
        for i, node in enumerate(self.nodes):
            nodes.append({
                "node": node,
                "status": "online",
                "uptime": self.get_uptime() + (i * 3600),  # Staggered start times
                "cpu": round(random.uniform(0.1, 0.8), 2),
                "maxcpu": 8,
                "mem": random.randint(2000000000, 8000000000),
                "maxmem": 16000000000,
                "disk": random.randint(50000000000, 200000000000),
                "maxdisk": 500000000000,
                "level": "",
                "id": f"node/{node}"
            })
        return nodes
        
    def get_node_status(self, node: str) -> Dict[str, Any]:
        """Get detailed status for a specific node"""
        return {
            "uptime": self.get_uptime(),
            "cpu": round(random.uniform(0.1, 0.8), 2),
            "cpuinfo": {
                "cores": 4,
                "cpus": 8,
                "mhz": "2400.000",
                "model": "Intel(R) Xeon(R) CPU E5-2620 v3",
                "sockets": 2
            },
            "memory": {
                "free": random.randint(8000000000, 12000000000),
                "total": 16000000000,
                "used": random.randint(4000000000, 8000000000)
            },
            "rootfs": {
                "avail": random.randint(200000000000, 400000000000),
                "free": random.randint(250000000000, 450000000000),
                "total": 500000000000,
                "used": random.randint(50000000000, 250000000000)
            },
            "swap": {
                "free": 8000000000,
                "total": 8000000000,
                "used": 0
            },
            "loadavg": [
                round(random.uniform(0.1, 2.0), 2),
                round(random.uniform(0.1, 2.0), 2),
                round(random.uniform(0.1, 2.0), 2)
            ],
            "kversion": "Linux 6.2.16-3-pve",
            "pveversion": "pve-manager/8.0.4/d258449d (running kernel: 6.2.16-3-pve)"
        }
        
    def get_storage(self, node: str) -> List[Dict[str, Any]]:
        """Get storage information for a node"""
        storage_list = []
        
        # Local storage
        storage_list.append({
            "storage": "local",
            "type": "dir",
            "active": 1,
            "avail": random.randint(200000000000, 400000000000),
            "content": "backup,iso,vztmpl",
            "path": "/var/lib/vz",
            "shared": 0,
            "total": 500000000000,
            "used": random.randint(50000000000, 250000000000)
        })
        
        # Local-lvm storage
        storage_list.append({
            "storage": "local-lvm",
            "type": "lvmthin",
            "active": 1,
            "avail": random.randint(800000000000, 1200000000000),
            "content": "images,rootdir",
            "shared": 0,
            "total": 1500000000000,
            "used": random.randint(300000000000, 700000000000)
        })
        
        return storage_list
        
    def get_vms(self, node: str) -> List[Dict[str, Any]]:
        """Get VMs running on a node"""
        vms = []
        
        # Generate 2-4 mock VMs per node
        vm_count = random.randint(2, 4)
        base_vmid = int(node[-1]) * 100 if node[-1].isdigit() else 100
        
        for i in range(vm_count):
            vmid = base_vmid + i + 1
            status = random.choice(["running", "stopped", "paused"])
            
            vm = {
                "vmid": vmid,
                "name": f"vm-{vmid}",
                "status": status,
                "maxmem": random.choice([2147483648, 4294967296, 8589934592]),
                "maxdisk": random.choice([21474836480, 42949672960, 85899345920]),
                "pid": random.randint(1000, 9999) if status == "running" else None,
                "qmpstatus": status,
                "tags": ""
            }
            
            if status == "running":
                vm.update({
                    "cpu": round(random.uniform(0.01, 0.5), 3),
                    "cpus": 2,
                    "mem": random.randint(1000000000, vm["maxmem"]),
                    "disk": random.randint(5000000000, vm["maxdisk"]),
                    "diskread": random.randint(1000000, 100000000),
                    "diskwrite": random.randint(1000000, 50000000),
                    "netin": random.randint(10000, 1000000),
                    "netout": random.randint(10000, 1000000),
                    "uptime": random.randint(3600, 86400)
                })
            
            vms.append(vm)
            
        return vms
        
    def get_containers(self, node: str) -> List[Dict[str, Any]]:
        """Get containers running on a node"""
        containers = []
        
        # Generate 1-3 mock containers per node
        container_count = random.randint(1, 3)
        base_ctid = int(node[-1]) * 100 + 50 if node[-1].isdigit() else 150
        
        for i in range(container_count):
            ctid = base_ctid + i + 1
            status = random.choice(["running", "stopped"])
            
            container = {
                "vmid": ctid,
                "name": f"ct-{ctid}",
                "status": status,
                "maxmem": random.choice([536870912, 1073741824, 2147483648]),
                "maxdisk": random.choice([8589934592, 21474836480]),
                "lock": None,
                "tags": ""
            }
            
            if status == "running":
                container.update({
                    "cpu": round(random.uniform(0.01, 0.3), 3),
                    "cpus": 1,
                    "mem": random.randint(100000000, container["maxmem"]),
                    "disk": random.randint(1000000000, container["maxdisk"]),
                    "diskread": random.randint(100000, 10000000),
                    "diskwrite": random.randint(100000, 5000000),
                    "netin": random.randint(1000, 100000),
                    "netout": random.randint(1000, 100000),
                    "uptime": random.randint(3600, 86400)
                })
            
            containers.append(container)
            
        return containers
        
    def get_network_config(self, node: str) -> List[Dict[str, Any]]:
        """Get network configuration for a node"""
        return [
            {
                "iface": "eth0",
                "type": "eth",
                "active": 1,
                "autostart": 1,
                "bridge_ports": None,
                "cidr": "192.168.1.10/24",
                "gateway": "192.168.1.1",
                "method": "static"
            },
            {
                "iface": "vmbr0",
                "type": "bridge",
                "active": 1,
                "autostart": 1,
                "bridge_ports": "eth0",
                "cidr": "192.168.1.10/24",
                "gateway": "192.168.1.1",
                "method": "static"
            }
        ]
        
    def get_pools(self) -> List[Dict[str, Any]]:
        """Get resource pools"""
        return [
            {
                "poolid": "production",
                "comment": "Production VMs and containers"
            },
            {
                "poolid": "development", 
                "comment": "Development environment"
            },
            {
                "poolid": "testing",
                "comment": "Testing and staging"
            }
        ]
        
    def get_cluster_status(self) -> List[Dict[str, Any]]:
        """Get cluster status information"""
        status = []
        
        for i, node in enumerate(self.nodes):
            status.append({
                "type": "node",
                "id": f"node/{node}",
                "name": node,
                "ip": f"192.168.1.{10 + i}",
                "level": "",
                "local": i == 0,
                "online": 1,
                "quorate": 1
            })
            
        # Add cluster info
        status.append({
            "type": "cluster",
            "id": "cluster",
            "name": "brewnix-test",
            "nodes": len(self.nodes),
            "quorate": 1,
            "version": 17
        })
        
        return status
        
    def get_users(self) -> List[Dict[str, Any]]:
        """Get system users"""
        return [
            {
                "userid": "root@pam",
                "comment": "System administrator",
                "enable": 1,
                "expire": 0,
                "firstname": "System",
                "lastname": "Administrator"
            },
            {
                "userid": "brewnix@pve",
                "comment": "Brewnix automation user",
                "enable": 1,
                "expire": 0,
                "groups": ["brewnix-admins"]
            }
        ]
