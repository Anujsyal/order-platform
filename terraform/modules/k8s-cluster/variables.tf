variable "name" {
  description = "Name prefix, e.g. order-platform-dev"
  type        = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "jenkins_security_group_id" {
  type = string
}

variable "admin_cidr" {
  type = string
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
  description = "pkgs.k8s.io channel. The kubeadm config uses v1beta4, so keep this at v1.31 or newer."
  type        = string
  default     = "v1.36"
}

variable "pod_cidr" {
  description = "Must match Calico's default IP pool"
  type        = string
  default     = "192.168.0.0/16"
}

variable "calico_version" {
  type    = string
  default = "v3.33.0"
}

variable "argocd_version" {
  type    = string
  default = "v3.5.6"
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the GitOps repo. Empty = don't install Argo CD (do it by hand)."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for node and audit logs"
  type        = number
  default     = 14
}
