variable "name" {
  type = string
}

variable "target_tag_key" {
  description = "EBS volumes with this tag are snapshotted. The gp3 StorageClass in incode-gitops sets it on every PV."
  type        = string
  default     = "Backup"
}

variable "target_tag_value" {
  description = "Project-specific value so other workloads in the account aren't swept in."
  type        = string
}

variable "daily_retention_count" {
  type    = number
  default = 14
}

variable "weekly_retention_count" {
  type    = number
  default = 5
}

variable "db_instance_ids" {
  description = "RDS instances whose backup/failure events alert to the SNS topic."
  type        = list(string)
  default     = []
}

variable "alert_emails" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
