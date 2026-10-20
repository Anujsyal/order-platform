output "master_public_ip" {
  value = module.cluster.master_public_ip
}

output "worker_public_ips" {
  value = module.cluster.worker_public_ips
}

output "worker_private_ips" {
  value = module.cluster.worker_private_ips
}

# Jenkins uses this (private IP, same VPC) for post-deploy verification.
# Put it in Jenkins as DEV_APP_URL / STAGING_APP_URL / PROD_APP_URL.
output "app_url_for_jenkins" {
  value = "http://${module.cluster.worker_private_ips[0]}:30080"
}

output "app_url" {
  value = "http://${module.cluster.worker_public_ips[0]}:30080"
}

output "argocd_url" {
  value = "https://${module.cluster.worker_public_ips[0]}:30443"
}

output "grafana_url" {
  value = "http://${module.cluster.worker_public_ips[0]}:30300"
}

output "prometheus_url" {
  value = "http://${module.cluster.worker_public_ips[0]}:30090"
}

output "ssh_master" {
  value = "ssh -i <path-to-${var.key_name}.pem> ubuntu@${module.cluster.master_public_ip}"
}

output "cloudwatch_dashboard" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${module.alarms.dashboard_name}"
}

output "cloudwatch_logs" {
  value = ["/${var.project}-${var.environment}/nodes", "/${var.project}-${var.environment}/k8s-audit"]
}
