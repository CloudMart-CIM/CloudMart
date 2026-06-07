locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Team        = var.team
    Owner       = var.owner
    ManagedBy   = "terraform"
    Module      = "cloud-infrastructure-management"
  }
}

resource "aws_sqs_queue" "order_events_dlq" {
  name = "${var.project_name}-order-events-dlq"

  message_retention_seconds = 1209600

  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-order-events-dlq"
    Service = "order-service"
  })
}

resource "aws_sqs_queue" "order_events" {
  name = "${var.project_name}-order-events"

  delay_seconds              = 0
  max_message_size           = 262144
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 10
  visibility_timeout_seconds = 30

  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_events_dlq.arn
    maxReceiveCount     = 5
  })

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-order-events"
    Service = "order-service"
  })
}