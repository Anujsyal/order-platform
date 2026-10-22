# One Kubernetes cluster per environment. Same code, different tfvars and a
# different state key - that is what "promoting infrastructure" means here:
# a change is applied to dev, then staging, then prod (Jenkinsfile.infra).
#
#   terraform init -reconfigure -backend-config=../../backend.hcl \
#                  -backend-config=key=cluster/dev/terraform.tfstate
#   terraform apply -var-file=envs/dev.tfvars

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Network, Jenkins SG and alert topic normally come from the shared stack. When
# VPC/Jenkins were built by hand (no shared state), set vpc_id & co. in tfvars.
data "terraform_remote_state" "shared" {
  count   = var.vpc_id == null ? 1 : 0
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "shared/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  shared                    = try(data.terraform_remote_state.shared[0].outputs, null)
  vpc_id                    = var.vpc_id != null ? var.vpc_id : local.shared.vpc_id
  subnet_ids                = var.vpc_id != null ? var.subnet_ids : local.shared.public_subnet_ids
  jenkins_security_group_id = var.vpc_id != null ? var.jenkins_security_group_id : local.shared.jenkins_security_group_id
  alerts_topic_arn          = var.vpc_id != null ? var.alerts_topic_arn : local.shared.alerts_topic_arn
}

module "cluster" {
  source = "../../modules/k8s-cluster"

  name                      = "${var.project}-${var.environment}"
  environment               = var.environment
  vpc_id                    = local.vpc_id
  subnet_ids                = local.subnet_ids
  jenkins_security_group_id = local.jenkins_security_group_id
  admin_cidr                = var.admin_cidr
  key_name                  = var.key_name
  master_instance_type      = var.master_instance_type
  worker_instance_type      = var.worker_instance_type
  worker_count              = var.worker_count
  kubernetes_minor_version  = var.kubernetes_minor_version
  gitops_repo_url           = var.gitops_repo_url
}

module "alarms" {
  source = "../../modules/cloudwatch-alarms"

  name        = var.project
  environment = var.environment
  instances = merge(
    { master = module.cluster.master_id },
    { for i, id in module.cluster.worker_ids : "worker-${i}" => id },
  )
  sns_topic_arn = local.alerts_topic_arn
}
