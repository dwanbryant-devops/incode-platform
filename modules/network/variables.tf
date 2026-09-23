variable "name" {
  description = "Name prefix, e.g. incode-dev."
  type        = string
}

variable "cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type    = number
  default = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "Use 2 or 3 AZs (RDS Multi-AZ and EKS both need at least 2)."
  }
}

variable "single_nat_gateway" {
  description = "One shared NAT (cheap, but an AZ outage cuts egress for all AZs) vs one per AZ (HA)."
  type        = bool
  default     = false
}

variable "enable_interface_endpoints" {
  description = "Create interface endpoints for ECR, STS, CloudWatch Logs, and Secrets Manager."
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  type    = bool
  default = true
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
