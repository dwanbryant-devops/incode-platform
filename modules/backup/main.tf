# AWS Backup: one encrypted vault, a daily plan, and tag-based selection.
# Anything tagged Backup=daily is covered: the RDS instance (tagged in the data module)
# and every EBS volume created by the gp3 StorageClass (tagged via the CSI driver).

resource "aws_kms_key" "backup" {
  description         = "${var.name} AWS Backup vault"
  enable_key_rotation = true
  tags                = var.tags
}

resource "aws_kms_alias" "backup" {
  name          = "alias/${var.name}-backup"
  target_key_id = aws_kms_key.backup.key_id
}

resource "aws_backup_vault" "this" {
  name          = "${var.name}-vault"
  kms_key_arn   = aws_kms_key.backup.arn
  force_destroy = !var.protect_recovery_points
  tags          = var.tags
}

resource "aws_backup_plan" "daily" {
  name = "${var.name}-daily"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 5 * * ? *)" # 05:00 UTC, after the RDS automated backup window
    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.daily_retention_days
    }

    recovery_point_tags = var.tags
  }

  rule {
    rule_name         = "weekly"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 6 ? * SUN *)"

    lifecycle {
      delete_after = var.weekly_retention_days
    }

    recovery_point_tags = var.tags
  }

  tags = var.tags
}

data "aws_iam_policy_document" "backup_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
  ])
  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

resource "aws_backup_selection" "tagged" {
  name         = "${var.name}-tagged"
  plan_id      = aws_backup_plan.daily.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = ["*"]

  condition {
    string_equals {
      key   = "aws:ResourceTag/Backup"
      value = "daily"
    }
    string_equals {
      key   = "aws:ResourceTag/Project"
      value = var.project
    }
  }
}

# Alert when a backup job fails.
# Not encrypted with the AWS-managed SNS key: AWS Backup can't publish to topics using it.
resource "aws_sns_topic" "backup_events" {
  name = "${var.name}-backup-events"
  tags = var.tags
}

data "aws_iam_policy_document" "backup_events" {
  statement {
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.backup_events.arn]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "backup_events" {
  arn    = aws_sns_topic.backup_events.arn
  policy = data.aws_iam_policy_document.backup_events.json
}

resource "aws_backup_vault_notifications" "this" {
  backup_vault_name   = aws_backup_vault.this.name
  sns_topic_arn       = aws_sns_topic.backup_events.arn
  backup_vault_events = ["BACKUP_JOB_FAILED", "BACKUP_JOB_EXPIRED", "RESTORE_JOB_FAILED", "COPY_JOB_FAILED"]
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.backup_events.arn
  protocol  = "email"
  endpoint  = each.value
}
