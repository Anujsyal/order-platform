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
# Security group: SSH + UI only from the admin IP, UI also from GitHub's
# webhook ranges so pushes trigger builds.
# ---------------------------------------------------------------------------
resource "aws_security_group" "jenkins" {
  name        = "${var.name}-jenkins-sg"
  description = "Jenkins controller"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-jenkins-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.jenkins.id
  description       = "SSH from admin"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "ui_admin" {
  security_group_id = aws_security_group.jenkins.id
  description       = "Jenkins UI from admin"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
}

resource "aws_vpc_security_group_ingress_rule" "ui_github_hooks" {
  for_each = toset(var.github_webhook_cidrs)

  security_group_id = aws_security_group.jenkins.id
  description       = "GitHub webhooks"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.jenkins.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# IAM: lets the infra pipeline run Terraform for the cluster stacks without
# storing AWS keys in Jenkins.
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

resource "aws_iam_role" "jenkins" {
  name               = "${var.name}-jenkins-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "ec2" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

data "aws_iam_policy_document" "state" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/*"]
  }
}

resource "aws_iam_role_policy" "state" {
  name   = "terraform-state"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.state.json
}

# The cluster stack also creates node IAM roles, CloudWatch alarms/dashboards
# and log groups. IAM is limited to resources named "<project>-*".
data "aws_iam_policy_document" "cluster_stack" {
  statement {
    sid = "NodeRoles"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:AttachRolePolicy",
      "iam:DetachRolePolicy", "iam:ListInstanceProfilesForRole", "iam:PassRole",
    ]
    resources = ["arn:aws:iam::*:role/${var.name}-*"]
  }
  statement {
    sid = "NodeInstanceProfiles"
    actions = [
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
    ]
    resources = ["arn:aws:iam::*:instance-profile/${var.name}-*"]
  }
  statement {
    sid = "Monitoring"
    actions = [
      "cloudwatch:PutMetricAlarm", "cloudwatch:PutCompositeAlarm", "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms", "cloudwatch:ListTagsForResource", "cloudwatch:TagResource",
      "cloudwatch:UntagResource", "cloudwatch:PutDashboard", "cloudwatch:GetDashboard",
      "cloudwatch:DeleteDashboards",
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DescribeLogGroups",
      "logs:ListTagsLogGroup", "logs:ListTagsForResource", "logs:TagResource", "logs:TagLogGroup",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cluster_stack" {
  name   = "cluster-stack"
  role   = aws_iam_role.jenkins.id
  policy = data.aws_iam_policy_document.cluster_stack.json
}

# Lets the CloudWatch agent on this box publish memory/disk metrics and logs.
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_cloudwatch_log_group" "jenkins" {
  name              = "/${var.name}-shared/jenkins"
  retention_in_days = 14
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.name}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

# ---------------------------------------------------------------------------
# Instance
# ---------------------------------------------------------------------------
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.jenkins.name
  user_data              = "#!/bin/bash\nexport CW_LOG_GROUP=\"${aws_cloudwatch_log_group.jenkins.name}\"\n${file("${path.module}/user_data.sh")}"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1          # containers can't reach instance credentials
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.volume_size
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-jenkins"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# Stable address so the Jenkins URL and GitHub webhook survive stop/start.
resource "aws_eip" "jenkins" {
  domain   = "vpc"
  instance = aws_instance.jenkins.id

  tags = {
    Name = "${var.name}-jenkins-eip"
  }
}
