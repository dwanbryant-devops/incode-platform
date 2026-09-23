output "db_address" {
  value = module.rds.db_instance_address
}

output "db_port" {
  value = 5432
}

output "db_name" {
  value = var.db_name
}

output "db_instance_identifier" {
  value = module.rds.db_instance_identifier
}

output "db_master_secret_arn" {
  description = "Secrets Manager secret (JSON: username, password) managed by RDS."
  value       = module.rds.db_instance_master_user_secret_arn
}

output "cache_secret_arn" {
  value = var.enable_cache ? aws_secretsmanager_secret.cache[0].arn : null
}

output "cache_replication_group_id" {
  value = var.enable_cache ? aws_elasticache_replication_group.cache[0].id : null
}
