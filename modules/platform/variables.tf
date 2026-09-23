variable "name" {
  description = "Name prefix, e.g. incode-dev."
  type        = string
}

variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "readable_secret_arns" {
  description = "Secrets Manager ARNs External Secrets may read (DB, cache)."
  type        = list(string)
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "gitops_repo_url" {
  type = string
}

variable "gitops_revision" {
  type    = string
  default = "main"
}

variable "argocd_chart_version" {
  type = string
}

variable "argocd_apps_chart_version" {
  type = string
}

variable "argocd_service_monitors" {
  description = "Enable once the Prometheus Operator CRDs exist (installed by Argo CD itself)."
  type        = bool
  default     = false
}

variable "extra_cluster_annotations" {
  description = "More facts for the gitops repo (e.g. DB endpoint and secret ARNs from the data layer)."
  type        = map(string)
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
