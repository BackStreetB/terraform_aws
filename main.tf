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
  description = "Allow from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

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

resource "aws_instance" "nginx" {
  ami                  = var.ami_id
  instance_type        = var.instance_type
  subnet_id            = aws_subnet.public_a.id
  security_groups      = [aws_security_group.ec2_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm_profile.name
  user_data            = file("userdata.sh")

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

resource "aws_cloudwatch_log_group" "nginx_error_log" {
  name              = "/var/log/nginx/error.log"
  retention_in_days = 7
  tags = local.common_tags
}

resource "aws_cloudwatch_log_metric_filter" "nginx_shutdown_filter" {
  name           = "${var.project}-nginx-shutdown-filter"
  log_group_name = aws_cloudwatch_log_group.nginx_error_log.name
  pattern        = "\"shutting down|exiting|exit\""
  metric_transformation {
    name      = "NginxDown"
    namespace = "Custom/Nginx"
    value     = "1"
  }
  depends_on = [aws_cloudwatch_log_group.nginx_error_log]
}

resource "aws_ssm_document" "cloudwatch_agent_config" {
  name          = "${var.project}-cw-agent-config"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Configure CloudWatch Agent to push nginx error log"
    parameters    = {}
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "configureCWAgent"
        inputs = {
          runCommand = [
            "sudo yum install -y amazon-cloudwatch-agent",
            "echo '{",
            "  \"logs\": {",
            "    \"logs_collected\": {",
            "      \"files\": {",
            "        \"collect_list\": [",
            "          {",
            "            \"file_path\": \"/var/log/nginx/error.log\",",
            "            \"log_group_name\": \"${aws_cloudwatch_log_group.nginx_error_log.name}\",",
            "            \"log_stream_name\": \"nginx-error\",",
            "            \"multi_line_start_pattern\": \"^\\\\[\"",
            "          }",
            "        ]",
            "      }",
            "    }",
            "  }",
            "}' | sudo tee /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json",
            "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a stop",
            "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a start -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s"
          ]
        }
      }
    ]
  })
}

resource "aws_ssm_association" "cw_agent_run" {
  name             = aws_ssm_document.cloudwatch_agent_config.name
  association_name = "${var.project}-cw-agent-association"

  targets {
    key    = "tag:Name"
    values = ["${var.project}-nginx-server"]
  }

  depends_on = [aws_instance.nginx, aws_cloudwatch_log_group.nginx_error_log]
}

resource "aws_cloudwatch_metric_alarm" "nginx_down" {
  alarm_name          = "${var.project}-nginx-down"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NginxDown"
  namespace           = "Custom/Nginx"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Trigger when NGINX is down"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.nginx.id
  }

  tags = local.common_tags
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
