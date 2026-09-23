output "dlm_policy_id" {
  value = aws_dlm_lifecycle_policy.ebs.id
}

output "events_topic_arn" {
  value = aws_sns_topic.backup_events.arn
}
