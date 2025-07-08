output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "nginx_instance_id" {
  description = "ID of the Nginx EC2 instance."
  value       = aws_instance.nginx.id
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer."
  value       = aws_lb.alb.dns_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts."
  value       = aws_sns_topic.alerts.arn
}

output "lambda_function_arn" {
  description = "ARN of the auto-healing Lambda function"
  value       = aws_lambda_function.recovery.arn
}

output "app_url" {
  description = "The application URL after Route 53 configuration."
  value       = "${var.domain_name}"
}

output "bastion_instance_id" {
  description = "ID of the Bastion Host EC2 instance."
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IPv4 address of the Bastion Host EC2 instance."
  value       = aws_instance.bastion.public_ip
}