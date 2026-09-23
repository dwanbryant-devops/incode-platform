# Shared backend settings for every dev layer; each layer sets its own `key`.
#   terraform init -backend-config=../backend.hcl
bucket       = "incode-tfstate-839553328184"
region       = "us-east-1"
encrypt      = true
use_lockfile = true
