# Caching tier: Valkey (Redis-compatible), primary + replica across AZs with automatic failover.

resource "aws_security_group" "cache" {
  count       = var.enable_cache ? 1 : 0
  name_prefix = "${var.name}-cache-"
  description = "Valkey from EKS pods only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-cache" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cache_from_eks" {
  count                        = var.enable_cache ? 1 : 0
  security_group_id            = aws_security_group.cache[0].id
  description                  = "Valkey from EKS nodes/pods"
  referenced_security_group_id = var.app_security_group_id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

# Own parameter group (the default one can't be modified). As a pure cache, evict
# least-recently-used keys when full instead of rejecting writes.
resource "aws_elasticache_parameter_group" "cache" {
  count  = var.enable_cache ? 1 : 0
  name   = "${var.name}-valkey8"
  family = "valkey8"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }

  tags = var.tags
}

resource "aws_elasticache_subnet_group" "cache" {
  count      = var.enable_cache ? 1 : 0
  name       = "${var.name}-cache"
  subnet_ids = var.database_subnet_ids
  tags       = var.tags
}

# ElastiCache has no "managed password" like RDS, so the token is generated here.
# It ends up in (encrypted, access-controlled) Terraform state: noted in known gaps.
resource "random_password" "cache_auth" {
  count   = var.enable_cache ? 1 : 0
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "cache" {
  count                   = var.enable_cache ? 1 : 0
  name                    = "${var.name}/cache"
  description             = "Valkey connection details for the RealWorld API"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "cache" {
  count     = var.enable_cache ? 1 : 0
  secret_id = aws_secretsmanager_secret.cache[0].id
  secret_string = jsonencode({
    host     = aws_elasticache_replication_group.cache[0].primary_endpoint_address
    port     = 6379
    password = random_password.cache_auth[0].result
    tls      = true
  })
}

resource "aws_elasticache_replication_group" "cache" {
  count                = var.enable_cache ? 1 : 0
  replication_group_id = "${var.name}-cache"
  description          = "RealWorld API cache"

  engine               = "valkey"
  engine_version       = "8.1"
  parameter_group_name = aws_elasticache_parameter_group.cache[0].name
  node_type            = var.cache_node_type
  port                 = 6379

  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.cache[0].name
  security_group_ids = [aws_security_group.cache[0].id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.cache_auth[0].result

  # Cache contents are disposable, but keep one daily snapshot for warm restarts.
  snapshot_retention_limit = 1
  snapshot_window          = "02:00-03:00"
  maintenance_window       = "sun:05:30-sun:06:30"

  apply_immediately = true

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.cache[0].name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "cache" {
  count             = var.enable_cache ? 1 : 0
  name              = "/aws/elasticache/${var.name}-cache"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}
