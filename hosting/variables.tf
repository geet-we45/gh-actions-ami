variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "custom_ami_name" {
  description = "Name for the custom AMI"
  type        = string
  default     = "amzn2-ami-hvm-*-x86_64-gp2"
}

variable "custom_ami_owner" {
  description = "Owner of the custom AMI"
  type        = string
  default     = "137112412989"
}
