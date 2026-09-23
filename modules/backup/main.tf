# Daily backups of mutable storage outside the database.
#
# AWS Backup is blocked in this account by an organization SCP, so:
#   - EBS volumes (every Kubernetes PV from the gp3 StorageClass): Data Lifecycle Manager
#     snapshots, selected by tag.
#   - RDS: native automated backups (daily snapshot + point-in-time recovery),
#     configured in the data module. Failures alert through the RDS event subscription below.

data "aws_iam_policy_document" "dlm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  name               = "${var.name}-dlm"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "ebs" {
  description        = "${var.name} daily and weekly EBS snapshots of Kubernetes volumes" # [A-Za-z0-9 _-] only
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags    = { (var.target_tag_key) = var.target_tag_value }

    schedule {
      name      = "daily"
      copy_tags = true
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["05:00"]
      }
      retain_rule {
        count = var.daily_retention_count
      }
      tags_to_add = { SnapshotSchedule = "daily" }
    }

    schedule {
      name      = "weekly"
      copy_tags = true
      create_rule {
        cron_expression = "cron(0 6 ? * SUN *)"
      }
      retain_rule {
        count = var.weekly_retention_count
      }
      tags_to_add = { SnapshotSchedule = "weekly" }
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Alerting: DLM policy errors and RDS backup failures -> SNS.
# ---------------------------------------------------------------------------
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
      identifiers = ["events.amazonaws.com", "rds.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "backup_events" {
  arn    = aws_sns_topic.backup_events.arn
  policy = data.aws_iam_policy_document.backup_events.json
}

resource "aws_cloudwatch_event_rule" "dlm_errors" {
  name        = "${var.name}-dlm-errors"
  description = "DLM snapshot policy entered an error state"
  event_pattern = jsonencode({
    source        = ["aws.dlm"]
    "detail-type" = ["DLM Policy State Change"]
    detail        = { state = ["ERROR"] }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "dlm_errors" {
  rule = aws_cloudwatch_event_rule.dlm_errors.name
  arn  = aws_sns_topic.backup_events.arn
}

resource "aws_db_event_subscription" "rds_backup" {
  count            = length(var.db_instance_ids) > 0 ? 1 : 0
  name             = "${var.name}-rds-backup"
  sns_topic        = aws_sns_topic.backup_events.arn
  source_type      = "db-instance"
  source_ids       = var.db_instance_ids
  event_categories = ["backup", "failure", "recovery"]
  tags             = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.backup_events.arn
  protocol  = "email"
  endpoint  = each.value
}
