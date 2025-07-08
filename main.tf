provider "aws" {
  region = var.region
}

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-vpc"
  })
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_a
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
  tags = merge(local.common_tags, { Name = "${var.project}-public-subnet-a" })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_b
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}b"
  tags = merge(local.common_tags, { Name = "${var.project}-public-subnet-b" })
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP and HTTPS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2-nginx-sg"
  description = "Allow traffic to Nginx instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "Allow Prometheus to scrape metrics"
    from_port   = 9113
    to_port     = 9113
    protocol    = "tcp"
    cidr_blocks = [var.monitoring_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-ec2-sg"
  })
}

# Ingress rules from bastion_sg to ec2_sg
resource "aws_security_group_rule" "ec2_ingress_ssh_from_bastion" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.ec2_sg.id
  source_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "ec2_ingress_3000_from_bastion" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  security_group_id = aws_security_group.ec2_sg.id
  source_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "ec2_ingress_9090_from_bastion" {
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  security_group_id = aws_security_group.ec2_sg.id
  source_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "ec2_ingress_9100_from_bastion" {
  type              = "ingress"
  from_port         = 9100
  to_port           = 9100
  protocol          = "tcp"
  security_group_id = aws_security_group.ec2_sg.id
  source_security_group_id = aws_security_group.bastion_sg.id
}

resource "aws_security_group_rule" "ec2_ingress_9115_from_bastion" {
  type              = "ingress"
  from_port         = 9115
  to_port           = 9115
  protocol          = "tcp"
  security_group_id = aws_security_group.ec2_sg.id
  source_security_group_id = aws_security_group.bastion_sg.id
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "ec2_ssm" {
  name = "nginx-autohealing-ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_attach" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent_logs" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_ssm_profile" {
  name = "nginx-autohealing-ec2-ssm-instance-profile"
  role = aws_iam_role.ec2_ssm.name
}

resource "aws_iam_role_policy" "ec2_ssm_session_manager" {
  name = "${var.project}-ec2-ssm-session-manager-policy"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:StartSession"
        ],
        Resource = [
          "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ssm:${var.region}::document/SSM-SessionManagerRunShell"
        ]
      }
    ]
  })
}

resource "aws_instance" "nginx" {
  ami                  = var.ami_id
  instance_type        = var.instance_type
  subnet_id            = aws_subnet.public_a.id
  security_groups      = [aws_security_group.ec2_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name
  user_data            = file("nginx_userdata.sh")

  tags = merge(local.common_tags, {
    Name = "${var.project}-nginx-server"
  })
}

resource "aws_lb" "alb" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = local.common_tags
}

resource "aws_lb_target_group" "tg" {
  name     = "${var.project}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_lb_target_group_attachment" "attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.nginx.id
  port             = 80
}

resource "aws_route53_record" "alb_dns" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_lambda_function" "recovery" {
  filename         = "lambda_function_updated.zip"
  function_name    = "${var.project}-auto-healer"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function_updated.handler"
  source_code_hash = filebase64sha256("lambda_function_updated.zip")
  runtime          = "python3.9"
  timeout          = 30

  environment {
    variables = {
      INSTANCE_IDS = aws_instance.nginx.id
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.recovery.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.recovery.arn
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project}-lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project}-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:DescribeInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:RebootInstances",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_metric_alarm" "nginx_down" {
  alarm_name          = "${var.project}-nginx-down"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors ec2 nginx instance is down"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    TargetGroup = aws_lb_target_group.tg.arn_suffix
    LoadBalancer = aws_lb.alb.arn_suffix
  }
}

resource "aws_iam_role_policy" "ec2_logs_inline" {
  name = "nginx-autohealing-ec2-logs-inline"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Resource = "*"
      }
    ]
  })
}

# Bastion Host Security Group
resource "aws_security_group" "bastion_sg" {
  name        = "${var.project}-bastion-sg"
  description = "Security group for the bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.bastion_ssh_cidr]
  }

  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_a.cidr_block]
  }

  egress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_a.cidr_block]
  }

  egress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_a.cidr_block]
  }

  egress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_a.cidr_block]
  }

  egress {
    from_port   = 9115
    to_port     = 9115
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_a.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-bastion-sg"
  })
}

# Bastion Host EC2 Instance
resource "aws_instance" "bastion" {
  ami                    = var.bastion_ami_id
  instance_type          = var.bastion_instance_type
  subnet_id              = aws_subnet.public_a.id # Place bastion in a public subnet
  security_groups        = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name # Attach SSM Instance Profile

  tags = merge(local.common_tags, {
    Name = "${var.project}-bastion-host"
  })
}

resource "aws_security_group" "promgraf_sg" {
  name        = "promgraf-sg"
  description = "Allow access to Prometheus and Grafana"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["${var.bastion_ssh_cidr}"] # Chỉ cho phép IP của bạn truy cập Prometheus
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["${var.bastion_ssh_cidr}"] # Chỉ cho phép IP của bạn truy cập Grafana
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "promgraf-sg" })
}

resource "aws_security_group_rule" "nginx_exporter_from_promgraf" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ec2_sg.id
  source_security_group_id = aws_security_group.promgraf_sg.id
}

resource "aws_instance" "promgraf" {
  ami                         = var.ami_id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.promgraf_sg.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm_profile.name
  tags = merge(local.common_tags, { Name = "promgraf-server" })
  user_data = <<-EOF
#!/bin/bash
set -ex
# Cài đặt Docker và docker-compose
amazon-linux-extras install docker -y
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
# Lấy private IP của Nginx instance
NGINX_IP="${aws_instance.nginx.private_ip}"
# Tạo file prometheus.yml
cat <<EOP > /home/ec2-user/prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'nginx'
    static_configs:
      - targets: ['${aws_instance.nginx.private_ip}:8000']
EOP
# Tạo file docker-compose.yml
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
cd /home/ec2-user
docker-compose up -d --force-recreate
chown ec2-user:ec2-user /home/ec2-user/prometheus.yml /home/ec2-user/docker-compose.yml
EOF
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "terraform-binhbe"
    key    = "terraform.tfstate"
    region = "ap-southeast-1"
  }
}
