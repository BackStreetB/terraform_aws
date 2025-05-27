variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_a" {
  description = "CIDR block for public subnet A"
  type        = string
}

variable "public_subnet_b" {
  description = "CIDR block for public subnet B"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "nginx-autohealing"
}

variable "alert_email" {
  description = "Email address to receive alert notifications"
  type        = string
}

variable "domain_name" {
  description = "Your domain name"
  type        = string
}

variable "hosted_zone_id" {
  description = "Your Route 53 hosted zone ID"
  type        = string
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  type        = string
}
