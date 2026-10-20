# Shared S3 backend settings. Each stack adds its own `key` at init time:
#   terraform init -backend-config=../../backend.hcl [-backend-config=key=...]
bucket       = "anujsyal-order-platform-tfstate"
region       = "ap-south-1"
encrypt      = true
use_lockfile = true
