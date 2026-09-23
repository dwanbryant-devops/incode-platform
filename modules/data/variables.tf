variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "database_subnet_ids" {
  type = list(string)
}

variable "database_subnet_group_name" {
  type = string
}

variable "app_security_group_id" {
  description = "Security group the app pods egress from (the EKS node SG)."
  type        = string
}

variable "postgres_version" {
  description = "Major or major.minor; minor upgrades are applied automatically in the maintenance window."
  type        = string
  default     = "18"
}

variable "rds_instance_class" {
  type    = string
  default = "db.t4g.small"
}

variable "rds_multi_az" {
  type    = bool
  default = true
}

variable "rds_max_storage_gb" {
  description = "Storage autoscaling ceiling."
  type        = number
  default     = 100
}

variable "rds_backup_retention_days" {
  type    = number
  default = 7
}

variable "db_name" {
  type    = string
  default = "realworld"
}

variable "db_username" {
  type    = string
  default = "realworld"
}

variable "deletion_protection" {
  description = "Also controls whether a final snapshot is taken on destroy."
  type        = bool
  default     = true
}

variable "enable_cache" {
  type    = bool
  default = true
}

variable "cache_node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
