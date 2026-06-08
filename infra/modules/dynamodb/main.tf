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

resource "aws_dynamodb_table" "products" {
  name         = "${var.project_name}-products"
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "name"
    type = "S"
  }

  attribute {
    name = "category"
    type = "S"
  }

  global_secondary_index {
    name            = "category-name-index"
    projection_type = "ALL"

    hash_key  = "category"
    range_key = "name"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = false

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-products"
    Service = "product-service"
  })
}