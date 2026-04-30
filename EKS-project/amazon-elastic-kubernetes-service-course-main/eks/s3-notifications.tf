####################################################################
#
# S3 Event Notification — Backup Completion
#
# Fires an SNS notification immediately when a new backup object
# is created under the backups/ prefix in the db_backups bucket.
#
# This is added to the existing s3-backup.tf bucket resource via
# a separate aws_s3_bucket_notification resource to keep concerns
# separated.
#
# Flow:
#   CronJob completes pg_dump → s3 cp
#     → S3 fires ObjectCreated event
#       → SNS backup_events topic
#         → Email to var.alert_email
#
####################################################################

resource "aws_s3_bucket_notification" "backup_notification" {
  bucket = aws_s3_bucket.db_backups.id

  topic {
    topic_arn     = aws_sns_topic.backup_events.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "backups/"
    filter_suffix = ".sql.gz"
  }

  depends_on = [aws_sns_topic_policy.backup_events_s3]
}
