#!/bin/bash

# Update system
yum update -y

# Install NGINX
amazon-linux-extras install nginx1 -y

# Start and enable Nginx
systemctl enable nginx
systemctl start nginx

# Install Python and Prometheus client
yum install -y python3-pip
pip3 install prometheus_client

# Create Python script for Nginx exporter
cat << EOF > /opt/nginx_monitor.py
from prometheus_client import start_http_server, Gauge
import time
import subprocess

nginx_up = Gauge('nginx_up', 'Nginx running status (1=up, 0=down)')

def check_nginx():
    try:
        # Use systemctl to check if nginx is active
        subprocess.check_output(['systemctl', 'is-active', '--quiet', 'nginx'])
        return 1
    except subprocess.CalledProcessError:
        # This error means the service is not active
        return 0

if __name__ == '__main__':
    # Start up the server to expose the metrics.
    start_http_server(8000)
    # Generate some requests.
    while True:
        status = check_nginx()
        nginx_up.set(status)
        time.sleep(15)
EOF

# Create systemd service for the Python exporter
cat << EOF > /etc/systemd/system/nginx-py-exporter.service
[Unit]
Description=Nginx Python Status Exporter
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/nginx_monitor.py
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Start and enable the exporter service
systemctl daemon-reload
systemctl enable nginx-py-exporter.service
systemctl start nginx-py-exporter.service 