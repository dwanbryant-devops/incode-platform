variable "name" {
  description = "Cluster name, e.g. incode-dev."
  type        = string
}

variable "kubernetes_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. GitHub-hosted runners have no fixed IPs, so CI needs 0.0.0.0/0 unless it uses self-hosted runners in the VPC."
  type        = list(string)
}

variable "cluster_admin_role_arns" {
  type = list(string)
}

variable "cluster_viewer_role_arns" {
  type    = list(string)
  default = []
}

variable "node_instance_types" {
  type = list(string)
}

variable "node_max_pods" {
  description = "kubelet maxPods; with VPC CNI prefix delegation EKS recommends 110 for instances under 30 vCPUs."
  type        = number
  default     = 110
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_min_size" {
  type = number
}

variable "node_max_size" {
  type = number
}

variable "node_desired_size" {
  type = number
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
