#!/bin/bash

# Update system
yum update -y

# Install NGINX
amazon-linux-extras install nginx1 -y

# Configure NGINX status page
cat > /etc/nginx/conf.d/status.conf << 'EOF'
server {
    listen 127.0.0.1:80;
    server_name localhost;

    location /status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

# Install NGINX Prometheus Exporter
wget https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v1.1.0/nginx-prometheus-exporter-1.1.0.linux-amd64.tar.gz
tar xvf nginx-prometheus-exporter-*.tar.gz
mv nginx-prometheus-exporter-* /opt/nginx-prometheus-exporter

# Create systemd service for NGINX Prometheus Exporter
cat > /etc/systemd/system/nginx-prometheus-exporter.service << 'EOF'
[Unit]
Description=NGINX Prometheus Exporter
After=nginx.service

[Service]
Type=simple
User=root
ExecStart=/opt/nginx-prometheus-exporter/nginx-prometheus-exporter -nginx.scrape-uri http://127.0.0.1/status
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start and enable services
systemctl daemon-reload
systemctl enable nginx
systemctl start nginx
systemctl enable nginx-prometheus-exporter
systemctl start nginx-prometheus-exporter

# Install CloudWatch Agent
yum install -y amazon-cloudwatch-agent

# Configure CloudWatch Agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/var/log/nginx/error.log",
            "log_stream_name": "{instance_id}",
            "multi_line_start_pattern": "^\\\\["
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch Agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Install Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.6.1/node_exporter-1.6.1.linux-amd64.tar.gz
tar xvfz node_exporter-1.6.1.linux-amd64.tar.gz
mv node_exporter-1.6.1.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.6.1.linux-amd64*

# Create systemd service for Node Exporter
cat << EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

# Install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xvfz prometheus-2.45.0.linux-amd64.tar.gz
mv prometheus-2.45.0.linux-amd64/prometheus /usr/local/bin/
mv prometheus-2.45.0.linux-amd64/promtool /usr/local/bin/
mkdir -p /etc/prometheus
mv prometheus-2.45.0.linux-amd64/consoles /etc/prometheus/
mv prometheus-2.45.0.linux-amd64/console_libraries /etc/prometheus/
rm -rf prometheus-2.45.0.linux-amd64*

# Create Prometheus config
cat << EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'blackbox'
    static_configs:
      - targets: ['localhost:9115']
    metrics_path: /probe
    params:
      module: [http_2xx]
      target: ['https://demo.awsthanhbinhit.com']
EOF

# Create systemd service for Prometheus
cat << EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml

[Install]
WantedBy=multi-user.target
EOF

# Install Blackbox Exporter
wget https://github.com/prometheus/blackbox_exporter/releases/download/v0.24.0/blackbox_exporter-0.24.0.linux-amd64.tar.gz
tar xvfz blackbox_exporter-0.24.0.linux-amd64.tar.gz
mv blackbox_exporter-0.24.0.linux-amd64/blackbox_exporter /usr/local/bin/
rm -rf blackbox_exporter-0.24.0.linux-amd64*

# Create Blackbox config
cat << EOF > /etc/blackbox_exporter/config.yml
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 204, 301, 302, 307, 308]
      method: GET
      preferred_ip_protocol: "ip4"
EOF

# Create systemd service for Blackbox
cat << EOF > /etc/systemd/system/blackbox_exporter.service
[Unit]
Description=Blackbox Exporter
After=network-online.target

[Service]
User=root
ExecStart=/usr/local/bin/blackbox_exporter --config.file=/etc/blackbox_exporter/config.yml

[Install]
WantedBy=multi-user.target
EOF

# Install Grafana
cat << EOF > /etc/yum.repos.d/grafana.repo
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

yum install -y grafana
systemctl enable grafana-server
systemctl start grafana-server

# Create custom metric script
cat << EOF > /usr/local/bin/check_nginx.sh
#!/bin/bash
if ! systemctl is-active --quiet nginx; then
    aws cloudwatch put-metric-data --namespace Custom/Nginx --metric-name NginxDown --value 1 --unit Count
else
    aws cloudwatch put-metric-data --namespace Custom/Nginx --metric-name NginxDown --value 0 --unit Count
fi
EOF

chmod +x /usr/local/bin/check_nginx.sh

# Add cron job to check nginx status every minute
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/check_nginx.sh") | crontab -
