output "vault_name" {
  value = aws_backup_vault.this.name
}

output "plan_id" {
  value = aws_backup_plan.daily.id
}

output "events_topic_arn" {
  value = aws_sns_topic.backup_events.arn
}
