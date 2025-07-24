variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "custom_ami_name" {
  description = "Name pattern of AMI to use for the instance"
  type        = string
}

variable "custom_ami_owner" {
  description = "Owner ID of the AMI (e.g., 'amazon' for Amazon Linux or AWS account ID for custom AMI)"
  type        = string
}