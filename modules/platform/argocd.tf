# Terraform installs only Argo CD, then hands off. Everything else in the cluster
# (add-ons and apps) is declared in the incode-gitops repo and synced by Argo CD.

resource "helm_release" "argocd" {
  name             = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  values = [yamlencode({
    dex = { enabled = false }
    configs = {
      params = {
        # UI is reached with `kubectl port-forward` only; no public ingress for Argo CD.
        "server.insecure" = true
      }
    }
    controller = { metrics = { enabled = true, serviceMonitor = { enabled = var.argocd_service_monitors } } }
    server     = { metrics = { enabled = true, serviceMonitor = { enabled = var.argocd_service_monitors } } }
    repoServer = { metrics = { enabled = true, serviceMonitor = { enabled = var.argocd_service_monitors } } }
  })]
}

# "GitOps bridge": register the local cluster with Argo CD and attach AWS facts
# that Terraform knows (role ARNs, VPC, secrets) as annotations. ApplicationSets in
# incode-gitops read them via the cluster generator, so no account-specific values
# are hardcoded in Git.
resource "kubernetes_secret_v1" "argocd_cluster" {
  metadata {
    name      = "in-cluster"
    namespace = helm_release.argocd.namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      environment                      = var.environment
    }
    annotations = merge(
      {
        aws_account_id              = data.aws_caller_identity.current.account_id
        aws_region                  = data.aws_region.current.region
        cluster_name                = var.cluster_name
        environment                 = var.environment
        vpc_id                      = var.vpc_id
        aws_lb_controller_role_arn  = module.irsa_lb_controller.arn
        cluster_autoscaler_role_arn = module.irsa_cluster_autoscaler.arn
        external_secrets_role_arn   = module.irsa_external_secrets.arn
        fluent_bit_role_arn         = module.irsa_fluent_bit.arn
        grafana_role_arn            = module.irsa_grafana.arn
        log_group_app               = aws_cloudwatch_log_group.k8s["app"].name
        log_group_platform          = aws_cloudwatch_log_group.k8s["platform"].name
        alb_logs_bucket             = aws_s3_bucket.alb_logs.bucket
        gitops_repo_url             = var.gitops_repo_url
        gitops_revision             = var.gitops_revision
      },
      var.extra_cluster_annotations,
    )
  }

  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }
}

# The single root Application ("app of apps"). It points at bootstrap/ in the gitops
# repo, which holds the ApplicationSets for add-ons and workloads.
resource "helm_release" "argocd_root" {
  name       = "argocd-root"
  namespace  = helm_release.argocd.namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      root = {
        namespace = helm_release.argocd.namespace
        project   = "default"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = "bootstrap"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = helm_release.argocd.namespace
        }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]

  depends_on = [kubernetes_secret_v1.argocd_cluster]
}
