variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "order-platform"
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "state_bucket" {
  description = "Bucket holding the shared stack's state (read for VPC/Jenkins outputs)"
  type        = string
}

# Optional overrides for when the shared stack was not applied (VPC and Jenkins
# built by hand). Setting vpc_id skips the shared remote state entirely.
variable "vpc_id" {
  type    = string
  default = null
}

variable "subnet_ids" {
  type    = list(string)
  default = null

  validation {
    condition     = var.subnet_ids == null || length(coalesce(var.subnet_ids, [])) > 0
    error_message = "subnet_ids must not be empty."
  }
}

variable "jenkins_security_group_id" {
  description = "Jenkins SG allowed to reach the NodePorts (post-deploy verification)"
  type        = string
  default     = null
}

variable "alerts_topic_arn" {
  description = "SNS topic for CloudWatch composite alarms; null = alarms without notifications"
  type        = string
  default     = null
}

variable "admin_cidr" {
  type = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "key_name" {
  type = string
}

variable "master_instance_type" {
  type    = string
  default = "c7i-flex.large"
}

variable "worker_instance_type" {
  type    = string
  default = "c7i-flex.large"
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "kubernetes_minor_version" {
  type    = string
  default = "v1.36"
}

variable "gitops_repo_url" {
  description = "Empty string = skip Argo CD bootstrap"
  type        = string
  default     = ""
}
