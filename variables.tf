variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "nginx-monitoring"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_a" {
  description = "CIDR block for public subnet A"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_b" {
  description = "CIDR block for public subnet B"
  type        = string
  default     = "10.0.2.0/24"
}

variable "ami_id" {
  description = "AMI ID for EC2 instance"
  type        = string
  default     = "ami-01030bb0f9b7640ac" # Amazon Linux 2 in ap-southeast-1
}

variable "instance_type" {
  description = "Instance type for EC2"
  type        = string
  default     = "t2.micro"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "demo.awsthanhbinhit.com"
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
  default     = "Z0138079289SZ7QRTK08M"
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS"
  type        = string
  default     = "arn:aws:acm:ap-southeast-1:637423552734:certificate/57d3f451-513b-4977-bfea-419c42111a5f"
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = "thanhbinhit.hcm@gmail.com"
}

variable "bastion_ssh_cidr" {
  description = "CIDR block for bastion host SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "bastion_ami_id" {
  description = "The AMI ID for the Bastion host."
  type        = string
  default     = "ami-01030bb0f9b7640ac" # Amazon Linux 2 in ap-southeast-1, same as nginx ami_id
}

variable "bastion_instance_type" {
  description = "The instance type for the Bastion host."
  type        = string
  default     = "t2.micro"
}

variable "monitoring_ami_id" {
  description = "AMI ID for the monitoring instance"
  type        = string
  default     = "ami-04173560437081c75" # Amazon Linux 2023 AMI in ap-southeast-1
}

variable "monitoring_instance_type" {
  description = "Instance type for the monitoring instance"
  type        = string
  default     = "t2.micro" # Free tier eligible
}
