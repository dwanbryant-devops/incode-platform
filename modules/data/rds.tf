resource "aws_security_group" "rds" {
  name_prefix = "${var.name}-rds-"
  description = "Postgres from EKS pods only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-rds" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Postgres from EKS nodes/pods"
  referenced_security_group_id = var.app_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.2"

  identifier = "${var.name}-postgres"

  engine               = "postgres"
  engine_version       = var.postgres_version
  family               = "postgres${split(".", var.postgres_version)[0]}"
  major_engine_version = split(".", var.postgres_version)[0]
  instance_class       = var.rds_instance_class

  allocated_storage     = 20
  max_allocated_storage = var.rds_max_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  port     = 5432

  # RDS generates the master password and keeps it in Secrets Manager; it never
  # appears in Terraform state or code. Rotation is off because the app reads the
  # secret at startup (see README: known gaps).
  manage_master_user_password          = true
  manage_master_user_password_rotation = false

  multi_az               = var.rds_multi_az
  db_subnet_group_name   = var.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Daily automated snapshots + point-in-time recovery (5-minute RPO). This is the
  # database backup; AWS Backup is blocked by an org SCP in this account.
  backup_retention_period = var.rds_backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "Sun:04:30-Sun:05:30"
  copy_tags_to_snapshot   = true

  deletion_protection              = var.deletion_protection
  skip_final_snapshot              = !var.deletion_protection
  final_snapshot_identifier_prefix = "${var.name}-final"

  # Observability: Performance Insights (7 days is free), enhanced OS metrics, logs to CloudWatch.
  performance_insights_enabled           = true
  performance_insights_retention_period  = 7
  monitoring_interval                    = 60
  create_monitoring_role                 = true
  monitoring_role_name                   = "${var.name}-rds-monitoring"
  enabled_cloudwatch_logs_exports        = ["postgresql", "upgrade"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  parameters = [
    { name = "rds.force_ssl", value = "1", apply_method = "pending-reboot" }, # as RDS records it; avoids a perpetual diff
    { name = "log_min_duration_statement", value = "500" },                   # log queries slower than 500ms
    { name = "log_connections", value = "all" },                              # Postgres 18: list of stages, not a boolean
    { name = "log_disconnections", value = "1" },
    { name = "shared_preload_libraries", value = "pg_stat_statements", apply_method = "pending-reboot" },
  ]

  tags = var.tags
}
