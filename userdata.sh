#!/bin/bash
yum update -y
yum install -y nginx aws-cli
systemctl enable nginx
systemctl start nginx
sleep 60

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
