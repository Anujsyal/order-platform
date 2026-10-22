environment          = "staging"
aws_region           = "ap-south-1"
project              = "order-platform"
state_bucket         = "anujsyal-order-platform-tfstate"
admin_cidr           = "122.161.52.142/32"
key_name             = "order-platform-key"
master_instance_type = "c7i-flex.large"
# 1 x 8 GB worker: fits the 16 vCPU quota (Jenkins 2 + dev 6 + staging 4 + prod 4)
worker_instance_type = "m7i-flex.large"
worker_count         = 1
gitops_repo_url      = "https://github.com/Anujsyal/order-platform-gitops.git"

# VPC and Jenkins were built by hand (default VPC), so there is no shared stack state
vpc_id                    = "vpc-01f42be464da4c4ac"
subnet_ids                = ["subnet-0b2d88050522e5506"]
jenkins_security_group_id = "sg-01d78008c7f4467ca"
