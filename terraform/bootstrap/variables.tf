variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "order-platform"
}

variable "state_bucket" {
  description = "Globally unique S3 bucket name for Terraform state"
  type        = string
  default     = "anujsyal-order-platform-tfstate"
}
