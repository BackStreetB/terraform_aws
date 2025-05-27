#!/bin/bash
yum update -y
yum install -y nginx aws-cli
systemctl enable nginx
systemctl start nginx
sleep 60

# Install Prometheus, Grafana, and Node Exporter
sudo yum update -y

# Install Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
tar xvfz node_exporter-1.3.1.linux-amd64.tar.gz
sudo mv node_exporter-1.3.1.linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-1.3.1.linux-amd64 node_exporter-1.3.1.linux-amd64.tar.gz

# Create Node Exporter service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=nginx
Group=nginx
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# Install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.33.0/prometheus-2.33.0.linux-amd64.tar.gz
tar xvfz prometheus-2.33.0.linux-amd64.tar.gz
sudo mv prometheus-2.33.0.linux-amd64/prometheus /usr/local/bin/
sudo mv prometheus-2.33.0.linux-amd64/promtool /usr/local/bin/
sudo mkdir /etc/prometheus
sudo mv prometheus-2.33.0.linux-amd64/consoles /etc/prometheus
sudo mv prometheus-2.33.0.linux-amd64/console_libraries /etc/prometheus
rm -rf prometheus-2.33.0.linux-amd64 prometheus-2.33.0.linux-amd64.tar.gz

# Create Prometheus configuration
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100'] # Node Exporter default port
EOF

# Create Prometheus service
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=nginx
Group=nginx
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

# Install Grafana
sudo tee /etc/yum.repos.d/grafana.repo > /dev/null <<EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1

[grafana-beta]
name=grafana-beta
baseurl=https://packages.grafana.com/beta/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
EOF

sudo yum install grafana -y
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

cat > /opt/check_nginx.sh << 'EOF'
#!/bin/bash
REGION="ap-southeast-1"
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
NGINX_STATUS=$(systemctl is-active nginx)
if [[ "$NGINX_STATUS" != "active" ]]; then
  VALUE=1
else
  VALUE=0
fi
aws cloudwatch put-metric-data \
  --namespace "Custom/Nginx" \
  --metric-name "NginxDown" \
  --dimensions InstanceId=$INSTANCE_ID \
  --value "$VALUE" \
  --region "$REGION"
EOF

chmod +x /opt/check_nginx.sh
(crontab -l 2>/dev/null; echo "* * * * * /opt/check_nginx.sh >> /var/log/nginx_check.log 2>&1") | crontab -
