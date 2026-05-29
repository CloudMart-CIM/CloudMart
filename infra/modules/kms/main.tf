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