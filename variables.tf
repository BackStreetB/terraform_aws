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
  description = "Email address for SNS alerts."
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

variable "bastion_ami_id" {
  description = "The AMI ID for the Bastion host."
  type        = string
}

variable "bastion_instance_type" {
  description = "The instance type for the Bastion host."
  type        = string
  default     = "t3.micro"
}

variable "bastion_ssh_cidr" {
  description = "The CIDR block that is allowed to SSH into the Bastion host."
  type        = string
  # !!! IMPORTANT: Replace with your actual public IP or a secure CIDR block !!!
  default     = "0.0.0.0/0" # <-- CHANGE THIS IN YOUR .tfvars or when applying
}
