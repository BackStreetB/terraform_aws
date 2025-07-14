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

# --- BỔ SUNG TỰ ĐỘNG CÀI ĐẶT VÀ CHẠY DOCKER COMPOSE ---
# Install Docker if not present
if ! command -v docker &> /dev/null; then
  amazon-linux-extras install docker -y
  systemctl enable docker
  systemctl start docker
  usermod -a -G docker ec2-user
fi

# Install Docker Compose if not present
if ! command -v docker-compose &> /dev/null; then
  curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose
  ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

# Create Prometheus config
echo "global:\n  scrape_interval: 15s\nscrape_configs:\n  - job_name: 'nginx'\n    static_configs:\n      - targets: ['127.0.0.1:8000']" > /home/ec2-user/prometheus.yml

# Create Docker Compose file
cat <<EOC > /home/ec2-user/docker-compose.yml
version: '3'
services:
  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
EOC

# Set permissions
chown ec2-user:ec2-user /home/ec2-user/prometheus.yml /home/ec2-user/docker-compose.yml

# Start Docker Compose
cd /home/ec2-user
sudo -u ec2-user /usr/local/bin/docker-compose down || true
sudo -u ec2-user /usr/local/bin/docker-compose up -d

# Ensure containers start on reboot
(crontab -l 2>/dev/null; echo "@reboot cd /home/ec2-user && /usr/local/bin/docker-compose up -d") | crontab - 