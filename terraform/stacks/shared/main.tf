# Shared infrastructure used by every environment: the VPC and the Jenkins
# controller. Applied from your laptop (Jenkins can't safely re-create itself).
#
#   terraform init -backend-config=../../backend.hcl
#   terraform apply

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  backend "s3" {
    key = "shared/terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project
      Environment = "shared"
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name = var.project
  cidr = var.vpc_cidr
}

module "jenkins" {
  source = "../../modules/jenkins"

  name          = var.project
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.public_subnet_ids[0]
  admin_cidr    = var.admin_cidr
  key_name      = var.key_name
  instance_type = var.jenkins_instance_type
  state_bucket  = var.state_bucket
}

# ---------------------------------------------------------------------------
# Out-of-band alerting: CloudWatch alarms from every stack notify this topic.
# AWS sends a confirmation email - click the link or nothing gets delivered.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

module "jenkins_alarms" {
  source = "../../modules/cloudwatch-alarms"

  name          = var.project
  environment   = "shared"
  instances     = { jenkins = module.jenkins.instance_id }
  sns_topic_arn = aws_sns_topic.alerts.arn
}
