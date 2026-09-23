locals {
  admin_entries = {
    for i, arn in var.cluster_admin_role_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Read-only, but includes Secrets: `terraform plan` on the platform layer needs to read Helm release state.
  viewer_entries = {
    for i, arn in var.cluster_viewer_role_arns : "viewer-${i}" => {
      principal_arn = arn
      policy_associations = {
        view = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.26"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Private endpoint for nodes; public endpoint for kubectl/CI, restricted by CIDR.
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.public_access_cidrs

  # Access entries only (no aws-auth ConfigMap). Admins are explicit, not "whoever ran terraform".
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries                           = merge(local.admin_entries, local.viewer_entries)

  # Control-plane logs to CloudWatch; Kubernetes Secrets envelope-encrypted with a module-managed KMS key.
  # Explicit key admins; the module default is "whoever runs terraform", which flips the
  # key policy between a laptop and CI on every apply.
  kms_key_administrators = var.cluster_admin_role_arns

  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  enable_irsa = true

  addons = {
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        # Kubernetes NetworkPolicy enforcement, used to isolate the app tiers.
        enableNetworkPolicy = "true"
        env = {
          # Assign /28 prefixes instead of single IPs: small instances get ~110 pod
          # slots instead of 17 (t3.medium), so density is limited by CPU/memory, not ENIs.
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    coredns    = {}
    kube-proxy = {}
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa.arn
    }
    metrics-server = {}
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # With prefix delegation the kubelet must be told it can run more pods.
      cloudinit_pre_nodeadm = [{
        content_type = "application/node.eks.aws"
        content      = <<-EOT
          apiVersion: node.eks.aws/v1alpha1
          kind: NodeConfig
          spec:
            kubelet:
              config:
                maxPods: ${var.node_max_pods}
        EOT
      }]

      labels = { role = "general" }

      # Tags so Cluster Autoscaler can discover and scale this group.
      tags = {
        "k8s.io/cluster-autoscaler/enabled"     = "true"
        "k8s.io/cluster-autoscaler/${var.name}" = "owned"
      }
    }
  }

  tags = var.tags
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name                  = "${var.name}-ebs-csi"
  use_name_prefix       = false
  attach_ebs_csi_policy = true

  oidc_providers = {
    this = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}
