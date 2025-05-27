output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "nginx_instance_id" {
  description = "ID of the NGINX EC2 instance"
  value       = aws_instance.nginx.id
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.alb.dns_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "lambda_function_arn" {
  description = "ARN of the auto-healing Lambda function"
  value       = aws_lambda_function.recovery.arn
}