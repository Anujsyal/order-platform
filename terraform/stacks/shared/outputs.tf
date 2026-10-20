output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "jenkins_security_group_id" {
  value = module.jenkins.security_group_id
}

output "jenkins_public_ip" {
  value = module.jenkins.public_ip
}

output "jenkins_url" {
  value = module.jenkins.url
}

output "jenkins_ssh" {
  value = "ssh -i <path-to-${var.key_name}.pem> ubuntu@${module.jenkins.public_ip}"
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${module.jenkins_alarms.dashboard_name}"
}
