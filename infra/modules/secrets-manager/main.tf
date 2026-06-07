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

# resource "random_password" "db_password" {
#   length           = 24
#   special          = true
#   override_special = "!#$%&*()-_=+[]{}<>:?"
# }

resource "random_password" "jwt_secret" {
  length           = 48
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "user_service_db" {
  name        = "${var.project_name}/${var.environment}/user-service/db"
  description = "Database credentials for CloudMart user-service"
  kms_key_id  = var.kms_key_arn
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-user-service-db-secret"
    Service = "user-service"
  })
}

resource "aws_secretsmanager_secret_version" "user_service_db" {
  secret_id = aws_secretsmanager_secret.user_service_db.id

  secret_string = jsonencode({
    DB_HOST     = var.db_host
    DB_PORT     = var.db_port
    DB_NAME     = var.db_name
    DB_USERNAME = var.db_username
    DB_PASSWORD = var.db_password
  })
}

resource "aws_secretsmanager_secret" "user_service_jwt" {
  name        = "${var.project_name}/${var.environment}/user-service/jwt"
  description = "JWT secret for CloudMart user-service"
  kms_key_id  = var.kms_key_arn
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-user-service-jwt-secret"
    Service = "user-service"
  })
}

resource "aws_secretsmanager_secret_version" "user_service_jwt" {
  secret_id = aws_secretsmanager_secret.user_service_jwt.id

  secret_string = jsonencode({
    JWT_SECRET = random_password.jwt_secret.result
  })
}

resource "aws_secretsmanager_secret" "notification_service" {
  name        = "${var.project_name}/${var.environment}/notification-service/config"
  description = "Configuration for CloudMart notification-service"
  kms_key_id  = var.kms_key_arn
  recovery_window_in_days = 0

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