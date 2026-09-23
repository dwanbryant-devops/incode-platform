terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    key = "dev/30-data/terraform.tfstate"
  }
}

locals {
  project     = "incode"
  environment = "dev"
  name        = "${local.project}-${local.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  network     = data.terraform_remote_state.network.outputs
  eks         = data.terraform_remote_state.eks.outputs
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = local.project
      Environment = local.environment
      ManagedBy   = "terraform"
      Layer       = "30-data"
    }
  }
}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "incode-tfstate-${local.account_id}"
    key    = "dev/10-network/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "incode-tfstate-${local.account_id}"
    key    = "dev/20-eks/terraform.tfstate"
    region = "us-east-1"
  }
}

module "data" {
  source = "../../../modules/data"

  name                       = local.name
  vpc_id                     = local.network.vpc_id
  database_subnet_ids        = local.network.database_subnet_ids
  database_subnet_group_name = local.network.database_subnet_group_name
  app_security_group_id      = local.eks.node_security_group_id

  postgres_version   = "18"
  rds_instance_class = "db.t4g.small"
  rds_multi_az       = true

  # Dev can be torn down without a final snapshot; AWS Backup still holds daily copies.
  deletion_protection = false

  enable_cache    = true
  cache_node_type = "cache.t4g.micro"

  log_retention_days = 14
}

module "backup" {
  source = "../../../modules/backup"

  name    = local.name
  project = local.project

  daily_retention_days    = 14
  weekly_retention_days   = 35
  protect_recovery_points = false
}

output "db_address" {
  value = module.data.db_address
}

output "db_port" {
  value = module.data.db_port
}

output "db_name" {
  value = module.data.db_name
}

output "db_instance_identifier" {
  value = module.data.db_instance_identifier
}

output "db_master_secret_arn" {
  value = module.data.db_master_secret_arn
}

output "cache_secret_arn" {
  value = module.data.cache_secret_arn
}

output "cache_replication_group_id" {
  value = module.data.cache_replication_group_id
}

output "backup_vault_name" {
  value = module.backup.vault_name
}
