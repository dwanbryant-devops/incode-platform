terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key = "dev/10-network/terraform.tfstate"
  }
}

locals {
  project     = "incode"
  environment = "dev"
  name        = "${local.project}-${local.environment}"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = local.project
      Environment = local.environment
      ManagedBy   = "terraform"
      Layer       = "10-network"
    }
  }
}

module "network" {
  source = "../../../modules/network"

  name     = local.name
  cidr     = "10.20.0.0/16"
  az_count = 3

  # Cost trade-offs for dev (see README): one NAT instead of one per AZ, and only the
  # free S3 gateway endpoint. Prod would set both to the HA/private options.
  single_nat_gateway         = true
  enable_interface_endpoints = false

  log_retention_days = 14
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr" {
  value = module.network.vpc_cidr
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "database_subnet_ids" {
  value = module.network.database_subnet_ids
}

output "database_subnet_group_name" {
  value = module.network.database_subnet_group_name
}
