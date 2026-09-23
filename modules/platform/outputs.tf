output "irsa_role_arns" {
  value = {
    aws_load_balancer_controller = module.irsa_lb_controller.arn
    cluster_autoscaler           = module.irsa_cluster_autoscaler.arn
    external_secrets             = module.irsa_external_secrets.arn
    fluent_bit                   = module.irsa_fluent_bit.arn
    grafana                      = module.irsa_grafana.arn
  }
}

output "log_groups" {
  value = { for k, lg in aws_cloudwatch_log_group.k8s : k => lg.name }
}

output "alb_logs_bucket" {
  value = aws_s3_bucket.alb_logs.bucket
}
