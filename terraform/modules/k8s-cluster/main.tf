locals {
  bootstrap_token = "${random_string.token_id.result}.${random_string.token_secret.result}"
  common_setup    = file("${path.module}/templates/common.sh")
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Join credentials
# The cluster CA is generated here instead of by kubeadm so that workers can
# pin it (--discovery-token-ca-cert-hash) rather than skipping CA verification.
# NOTE: the CA key ends up in Terraform state and master user-data - keep the
# state bucket private (it is) and treat it as a secret.
# ---------------------------------------------------------------------------
resource "random_string" "token_id" {
  length  = 6
  upper   = false
  special = false
}

resource "random_string" "token_secret" {
  length  = 16
  upper   = false
  special = false
}

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600

  subject {
    common_name = "kubernetes"
  }

  allowed_uses = ["cert_signing", "key_encipherment", "digital_signature"]
}

# ---------------------------------------------------------------------------
# IAM + log groups for the CloudWatch agent (memory/disk metrics, logs).
# Hop limit 1 on IMDS means only host processes (the agent), not pods, can
# use this role.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-k8s-node-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-k8s-node-profile"
  role = aws_iam_role.node.name
}

# Created up front so retention is set (the agent would create them with "never expire").
resource "aws_cloudwatch_log_group" "nodes" {
  name              = "/${var.name}/nodes"
  retention_in_days = var.log_retention_days
}

# API server audit log shipped off-host: an attacker with root on the master
# can't quietly erase the trail.
resource "aws_cloudwatch_log_group" "audit" {
  name              = "/${var.name}/k8s-audit"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# Security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "cluster" {
  name        = "${var.name}-k8s-sg"
  description = "Kubernetes ${var.environment} cluster nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-k8s-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "node_to_node" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "All traffic between cluster nodes (kubelet, Calico IPIP/BGP, etcd)"
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "ssh_admin" {
  security_group_id = aws_security_group.cluster.id
  description       = "SSH from admin"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "api_admin" {
  security_group_id = aws_security_group.cluster.id
  description       = "Kubernetes API from admin"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

resource "aws_vpc_security_group_ingress_rule" "nodeports_admin" {
  security_group_id = aws_security_group.cluster.id
  description       = "NodePorts (app, Argo CD, Grafana) from admin"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
}

resource "aws_vpc_security_group_ingress_rule" "nodeports_jenkins" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "NodePorts from Jenkins (post-deploy verification)"
  referenced_security_group_id = var.jenkins_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# Control plane
# ---------------------------------------------------------------------------
resource "aws_instance" "master" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.master_instance_type
  subnet_id              = var.subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/templates/master.sh.tpl", {
    common_setup    = local.common_setup
    log_group       = "/${var.name}"
    k8s_minor       = var.kubernetes_minor_version
    bootstrap_token = local.bootstrap_token
    ca_crt          = tls_self_signed_cert.ca.cert_pem
    ca_key          = tls_private_key.ca.private_key_pem
    pod_cidr        = var.pod_cidr
    calico_version  = var.calico_version
    argocd_version  = var.argocd_version
    gitops_repo_url = var.gitops_repo_url
    environment     = var.environment
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1 # pods cannot reach instance metadata
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-master"
    Role = "control-plane"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ---------------------------------------------------------------------------
# Workers
# ---------------------------------------------------------------------------
resource "aws_instance" "worker" {
  count = var.worker_count

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.worker_instance_type
  subnet_id              = element(var.subnet_ids, count.index)
  vpc_security_group_ids = [aws_security_group.cluster.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/templates/worker.sh.tpl", {
    common_setup    = local.common_setup
    log_group       = "/${var.name}"
    k8s_minor       = var.kubernetes_minor_version
    bootstrap_token = local.bootstrap_token
    ca_crt          = tls_self_signed_cert.ca.cert_pem
    master_ip       = aws_instance.master.private_ip
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-worker-${count.index}"
    Role = "worker"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
