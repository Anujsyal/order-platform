variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "order-platform"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "admin_cidr" {
  description = "Your public IP as x.x.x.x/32 - only this address gets SSH/UI access"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "key_name" {
  description = "Existing EC2 key pair name"
  type        = string
}

variable "jenkins_instance_type" {
  type    = string
  default = "c7i-flex.large"
}

variable "state_bucket" {
  type = string
}

variable "alert_email" {
  description = "Email that receives CloudWatch alarm notifications (confirm the subscription mail!)"
  type        = string
}
