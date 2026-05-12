variable "alert_email" {}


resource "aws_sns_topic" "rds_alarms" {
  name = "rds-alarms"

  tags = {
   Name    = "rds-alarms"
  Purpose = "RDS CPU, storage, and status alerts"
  }
}

resource "aws_sns_topic_subscription" "rds_alarms_email" {
  topic_arn = aws_sns_topic.rds_alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

output "sns_topic_arn" {
  value = aws_sns_topic.rds_alarms.arn
}