variable "name" {
  type = string
}

variable "project" {
  description = "Selection only picks up resources with this Project tag, so other workloads in the account aren't swept in."
  type        = string
}

variable "daily_retention_days" {
  type    = number
  default = 14
}

variable "weekly_retention_days" {
  type    = number
  default = 35
}

variable "protect_recovery_points" {
  description = "When false, the vault can be destroyed with recovery points in it (useful for throwaway envs)."
  type        = bool
  default     = true
}

variable "alert_emails" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
