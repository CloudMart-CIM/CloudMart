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

resource "aws_ses_email_identity" "notification_sender" {
  count = var.ses_verified_email != "" ? 1 : 0

  email = var.ses_verified_email
}

resource "aws_secretsmanager_secret" "notification_service" {
  name        = "${var.project_name}/${var.environment}/notification-service/config"
  description = "Configuration for CloudMart notification-service"
  kms_key_id  = var.kms_key_arn

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-notification-service-config-secret"
    Service = "notification-service"
  })
}

resource "aws_secretsmanager_secret_version" "notification_service" {
  secret_id = aws_secretsmanager_secret.notification_service.id

  secret_string = jsonencode({
    SES_REGION       = var.aws_region
    SES_SENDER_EMAIL = var.ses_verified_email
    SQS_QUEUE_URL    = var.sqs_queue_url
  })
}