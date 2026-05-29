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

resource "aws_kms_key" "cloudmart" {
  description             = "CloudMart customer managed KMS key for RDS, DynamoDB, SQS and Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-kms-key"
  })
}

resource "aws_kms_alias" "cloudmart" {
  name          = "alias/${var.project_name}-kms"
  target_key_id = aws_kms_key.cloudmart.key_id
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
  kms_key_id  = aws_kms_key.cloudmart.arn

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
  kms_key_id  = aws_kms_key.cloudmart.arn

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