variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "instances" {
  description = "Map of logical name (e.g. master, worker-0) => EC2 instance ID"
  type        = map(string)
}

variable "sns_topic_arn" {
  description = "Topic that receives composite alarm notifications (null = alarms only, no notifications)"
  type        = string
  default     = null
}

variable "cpu_threshold" {
  type    = number
  default = 85
}

variable "memory_threshold" {
  type    = number
  default = 90
}

variable "disk_threshold" {
  type    = number
  default = 85
}
