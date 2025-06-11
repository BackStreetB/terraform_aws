#!/bin/bash

# Update system
yum update -y

# Install required packages
yum install -y wget tar

# Install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.52.0/prometheus-2.52.0.linux-amd64.tar.gz
tar xvf prometheus-*.tar.gz
mv prometheus-* /opt/prometheus

# Create Prometheus systemd service
cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/prometheus/prometheus --config.file=/opt/prometheus/prometheus.yml --storage.tsdb.path=/opt/prometheus/data --web.console.templates=/opt/prometheus/consoles --web.console.libraries=/opt/prometheus/console_libraries
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Configure Prometheus
cat > /opt/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'nginx'
    static_configs:
      - targets: ['${aws_instance.nginx.private_ip}:9113']
    metrics_path: '/metrics'

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF

# Install Grafana
cat > /etc/yum.repos.d/grafana.repo << 'EOF'
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

# Configure Grafana
cat > /etc/grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
EOF

# Start and enable services
systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus
systemctl enable grafana-server
systemctl start grafana-server

# Install CloudWatch Agent
yum install -y amazon-cloudwatch-agent

# Configure CloudWatch Agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "metrics": {
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}"
    },
    "metrics_collected": {
      "prometheus": {
        "prometheus_config_path": "/opt/aws/amazon-cloudwatch-agent/etc/prometheus.yaml",
        "emf_processor": {
          "metric_namespace": "Nginx"
        }
      }
    }
  }
}
EOF

# Configure Prometheus for CloudWatch
cat > /opt/aws/amazon-cloudwatch-agent/etc/prometheus.yaml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'nginx'
    static_configs:
      - targets: ['${aws_instance.nginx.private_ip}:9113']
    metrics_path: '/metrics'
EOF

# Start CloudWatch Agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent 