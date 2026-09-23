terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }

  backend "s3" {
    key = "dev/40-platform/terraform.tfstate"
  }
}

locals {
  project     = "incode"
  environment = "dev"
  region      = "us-east-1"
  name        = "${local.project}-${local.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  network     = data.terraform_remote_state.network.outputs
  eks         = data.terraform_remote_state.eks.outputs
  data        = data.terraform_remote_state.data.outputs

  # Short-lived token from the caller's AWS identity; needs the AWS CLI on the path.
  k8s_exec = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.eks.cluster_name, "--region", local.region]
  }
}

provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project     = local.project
      Environment = local.environment
      ManagedBy   = "terraform"
      Layer       = "40-platform"
    }
  }
}

provider "kubernetes" {
  host                   = local.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(local.eks.cluster_certificate_authority_data)
  exec {
    api_version = local.k8s_exec.api_version
    command     = local.k8s_exec.command
    args        = local.k8s_exec.args
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(local.eks.cluster_certificate_authority_data)
    exec                   = local.k8s_exec
  }
}

data "aws_caller_identity" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "incode-tfstate-${local.account_id}"
    key    = "dev/10-network/terraform.tfstate"
    region = local.region
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "incode-tfstate-${local.account_id}"
    key    = "dev/20-eks/terraform.tfstate"
    region = local.region
  }
}

data "terraform_remote_state" "data" {
  backend = "s3"
  config = {
    bucket = "incode-tfstate-${local.account_id}"
    key    = "dev/30-data/terraform.tfstate"
    region = local.region
  }
}

module "platform" {
  source = "../../../modules/platform"

  name              = local.name
  project           = local.project
  environment       = local.environment
  cluster_name      = local.eks.cluster_name
  oidc_provider_arn = local.eks.oidc_provider_arn
  vpc_id            = local.network.vpc_id

  readable_secret_arns = compact([local.data.db_master_secret_arn, local.data.cache_secret_arn])

  gitops_repo_url           = "https://github.com/dwanbryant-devops/incode-gitops.git"
  gitops_revision           = "main"
  argocd_chart_version      = "10.9.2"
  argocd_apps_chart_version = "2.0.5"

  extra_cluster_annotations = {
    db_host          = local.data.db_address
    db_port          = tostring(local.data.db_port)
    db_name          = local.data.db_name
    db_secret_arn    = local.data.db_master_secret_arn
    cache_secret_arn = local.data.cache_secret_arn != null ? local.data.cache_secret_arn : ""
  }

  log_retention_days = 14
}

output "irsa_role_arns" {
  value = module.platform.irsa_role_arns
}

output "log_groups" {
  value = module.platform.log_groups
}

output "alb_logs_bucket" {
  value = module.platform.alb_logs_bucket
}
