variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "custom_ami_owner" {
  description = "Owner of the custom AMI"
  type        = string
}

