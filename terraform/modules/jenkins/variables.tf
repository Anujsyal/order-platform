variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form (x.x.x.x/32)"
  type        = string
}

variable "key_name" {
  description = "Existing EC2 key pair name for SSH"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "c7i-flex.large"
}

variable "volume_size" {
  type    = number
  default = 30
}

variable "state_bucket" {
  description = "Terraform state bucket the infra pipeline reads/writes"
  type        = string
}

variable "github_webhook_cidrs" {
  description = "GitHub hook source ranges (https://api.github.com/meta -> hooks)"
  type        = list(string)
  default     = ["192.30.252.0/22", "185.199.108.0/22", "140.82.112.0/20", "143.55.64.0/20"]
}
