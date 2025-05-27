# Nginx Auto-healing ALB System

This project implements an auto-healing system for Nginx servers running on AWS, with automatic detection and recovery mechanisms.

## System Architecture

### Components

1. **Network Layer**
   - VPC with 2 public subnets across different AZs
   - Internet Gateway and Route Tables
   - Security Groups for ALB and EC2

2. **Application Layer**
   - Nginx server on EC2
   - Application Load Balancer (ALB)
   - Route53 DNS configuration
   - SSL/TLS via ACM

3. **Monitoring & Logging**
   - CloudWatch Log Groups
   - CloudWatch Agent
   - Metric Filters for error detection
   - CloudWatch Alarms

4. **Auto-healing System**
   - SNS Topics for notifications
   - Lambda function for recovery
   - IAM roles and policies

## Prerequisites

- AWS Account with appropriate permissions
- Terraform installed (version >= 0.12)
- AWS CLI configured
- Domain name and hosted zone in Route53
- SSL Certificate in ACM

## Required Variables

Create a `terraform.tfvars` file with the following variables:

```hcl
region              = "your-aws-region"
environment         = "production"
project             = "nginx-autohealing"
vpc_cidr           = "10.0.0.0/16"
public_subnet_a    = "10.0.1.0/24"
public_subnet_b    = "10.0.2.0/24"
ami_id             = "your-ami-id"
instance_type      = "t2.micro"
domain_name        = "your-domain.com"
hosted_zone_id     = "your-hosted-zone-id"
acm_certificate_arn = "your-acm-certificate-arn"
alert_email        = "your-email@domain.com"
```

## Deployment Steps

1. **Initialize Terraform**
   ```bash
   terraform init
   ```

2. **Review the execution plan**
   ```bash
   terraform plan
   ```

3. **Apply the configuration**
   ```bash
   terraform apply
   ```

4. **Verify the deployment**
   - Check ALB DNS name
   - Verify Nginx is running
   - Test HTTPS redirection
   - Confirm CloudWatch logs are being collected

## System Flow

1. **Normal Operation**
   - Traffic flows through ALB to Nginx server
   - CloudWatch Agent collects and forwards logs
   - System continuously monitors for issues

2. **Issue Detection**
   - CloudWatch Metric Filters monitor for:
     - "nginx fail"
     - "nginx down"
     - "nginx error"
   - When issues are detected, CloudWatch Alarm triggers

3. **Auto-healing Process**
   - SNS Topic sends notification to configured email
   - Lambda function is invoked
   - Recovery actions are executed
   - System returns to normal operation

## Monitoring

- CloudWatch Logs: `/var/log/nginx/error.log`
- CloudWatch Metrics: `Custom/Nginx` namespace
- CloudWatch Alarms: `NginxDown` metric

## Security

- HTTPS enforced with HTTP to HTTPS redirection
- Security groups restrict access
- IAM roles with least privilege principle
- SSL/TLS encryption

## Maintenance

- Logs are retained for 7 days
- CloudWatch Agent configuration can be updated via SSM
- Lambda function can be modified for different recovery strategies

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

## Troubleshooting

1. **Nginx not starting**
   - Check EC2 instance status
   - Review CloudWatch logs
   - Verify security group rules

2. **ALB issues**
   - Confirm target group health
   - Check security group configurations
   - Verify SSL certificate

3. **Auto-healing not working**
   - Check Lambda function logs
   - Verify SNS topic configuration
   - Review IAM permissions

## Contributing

Feel free to submit issues and enhancement requests. 