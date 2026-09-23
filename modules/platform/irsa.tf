# One IAM role per add-on, trusted only by that add-on's Kubernetes service account (IRSA).
# Namespaces/service-account names must match the charts in incode-gitops.

locals {
  irsa_oidc = { provider_arn = var.oidc_provider_arn }
}

module "irsa_lb_controller" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name                                   = "${var.name}-aws-load-balancer-controller"
  use_name_prefix                        = false
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    this = merge(local.irsa_oidc, { namespace_service_accounts = ["kube-system:aws-load-balancer-controller"] })
  }
  tags = var.tags
}

module "irsa_cluster_autoscaler" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name                             = "${var.name}-cluster-autoscaler"
  use_name_prefix                  = false
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.cluster_name]

  oidc_providers = {
    this = merge(local.irsa_oidc, { namespace_service_accounts = ["kube-system:cluster-autoscaler"] })
  }
  tags = var.tags
}

module "irsa_external_secrets" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name                                  = "${var.name}-external-secrets"
  use_name_prefix                       = false
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = var.readable_secret_arns
  external_secrets_ssm_parameter_arns   = []

  oidc_providers = {
    this = merge(local.irsa_oidc, { namespace_service_accounts = ["external-secrets:external-secrets"] })
  }
  tags = var.tags
}

# Fluent Bit: write-only to the pre-created log groups.
data "aws_iam_policy_document" "fluent_bit" {
  statement {
    actions = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = flatten([
      for lg in aws_cloudwatch_log_group.k8s : [lg.arn, "${lg.arn}:*"]
    ])
  }
  statement {
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
}

module "irsa_fluent_bit" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name                           = "${var.name}-fluent-bit"
  use_name_prefix                = false
  create_inline_policy           = true
  source_inline_policy_documents = [data.aws_iam_policy_document.fluent_bit.json]

  oidc_providers = {
    this = merge(local.irsa_oidc, { namespace_service_accounts = ["logging:fluent-bit"] })
  }
  tags = var.tags
}

# Grafana: read CloudWatch metrics and Logs Insights, so RDS/ALB/ElastiCache
# dashboards sit next to the Prometheus ones.
data "aws_iam_policy_document" "grafana" {
  statement {
    actions = [
      "cloudwatch:DescribeAlarmsForMetric", "cloudwatch:DescribeAlarmHistory", "cloudwatch:DescribeAlarms",
      "cloudwatch:ListMetrics", "cloudwatch:GetMetricData", "cloudwatch:GetInsightRuleReport",
      "logs:DescribeLogGroups", "logs:GetLogGroupFields", "logs:StartQuery", "logs:StopQuery",
      "logs:GetQueryResults", "logs:GetLogEvents",
      "ec2:DescribeTags", "ec2:DescribeInstances", "ec2:DescribeRegions",
      "tag:GetResources",
    ]
    resources = ["*"]
  }
}

module "irsa_grafana" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.8"

  name                           = "${var.name}-grafana"
  use_name_prefix                = false
  create_inline_policy           = true
  source_inline_policy_documents = [data.aws_iam_policy_document.grafana.json]

  oidc_providers = {
    this = merge(local.irsa_oidc, { namespace_service_accounts = ["monitoring:grafana"] })
  }
  tags = var.tags
}
