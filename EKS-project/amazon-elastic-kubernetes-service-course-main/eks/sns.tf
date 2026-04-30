####################################################################
#
# SNS Topics — one per concern
#
# Three topics:
#   1. eks-alarms    — EKS node CPU/status alerts
#   2. rds-alarms    — RDS CPU/storage/status alerts
#   3. backup-events — S3 backup completion notifications
#
# All subscribed to the same email address via var.alert_email.
# Subscriptions require manual confirmation — AWS will send a
# confirmation email to the address after terraform apply. 
# CHECK SPAM FOLDER IF YOU DON'T SEE IT.
#
####################################################################

####################################################################
# SNS Topics
####################################################################

resource "aws_sns_topic" "eks_alarms" {
  name = "eks-node-alarms"

 # tags = {
 #  Name    = "eks-node-alarms"
 #   Purpose = "EKS node CPU and status check alerts"
 # }
}

# Issue with tags, probably lab environment, so ignoring for now

resource "aws_sns_topic" "rds_alarms" {
  name = "eks-rds-alarms"

 # tags = {
 #   Name    = "eks-rds-alarms"
 #  Purpose = "RDS CPU, storage, and status alerts"
 # }
}

resource "aws_sns_topic" "backup_events" {
  name = "eks-backup-events"

 # tags = {
 #   Name    = "eks-backup-events"
 #   Purpose = "S3 backup completion notifications"
 # }
}

####################################################################
# Email Subscriptions — all pointing to same address
####################################################################

resource "aws_sns_topic_subscription" "eks_alarms_email" {
  topic_arn = aws_sns_topic.eks_alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "rds_alarms_email" {
  topic_arn = aws_sns_topic.rds_alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "backup_events_email" {
  topic_arn = aws_sns_topic.backup_events.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

####################################################################
# SNS Topic Policy for S3 — allows the backup bucket to publish
# to the backup_events topic when a new object is created
####################################################################

resource "aws_sns_topic_policy" "backup_events_s3" {
  arn = aws_sns_topic.backup_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.backup_events.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.db_backups.arn
          }
        }
      }
    ]
  })
}

####################################################################
# Outputs
####################################################################

output "sns_eks_alarms_arn" {
  value = aws_sns_topic.eks_alarms.arn
}

output "sns_rds_alarms_arn" {
  value = aws_sns_topic.rds_alarms.arn
}

output "sns_backup_events_arn" {
  value = aws_sns_topic.backup_events.arn
}
