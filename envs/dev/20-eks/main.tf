terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    key = "dev/20-eks/terraform.tfstate"
  }
}

locals {
  project     = "incode"
  environment = "dev"
  name        = "${local.project}-${local.environment}"
  account_id  = data.aws_caller_identity.current.account_id
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = local.project
      Environment = local.environment
      ManagedBy   = "terraform"
      Layer       = "20-eks"
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

module "eks" {
  source = "../../../modules/eks"

  name               = local.name
  kubernetes_version = "1.35" # one behind latest, so add-on charts have caught up

  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  # GitHub-hosted runners have no stable IPs; see README known gaps.
  public_access_cidrs = ["0.0.0.0/0"]

  cluster_admin_role_arns = [
    "arn:aws:iam::${local.account_id}:role/admin",        # humans (MFA-protected)
    "arn:aws:iam::${local.account_id}:role/gha-tf-apply", # CI apply (installs Argo CD)
  ]
  cluster_viewer_role_arns = [
    "arn:aws:iam::${local.account_id}:role/gha-tf-plan",
  ]

  node_instance_types = ["t3.large"]
  node_min_size       = 2
  node_desired_size   = 2
  node_max_size       = 5

  log_retention_days = 14
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  value = module.eks.node_security_group_id
}
