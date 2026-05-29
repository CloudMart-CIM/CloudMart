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
    name = "description"
    type = "S"
  }

  attribute {
    name = "price"
    type = "N"
  }

  attribute {
    name = "category"
    type = "S"
  }

  attribute {
    name = "stock"
    type = "N"
  }

  attribute {
    name = "imageUrl"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "nameCategoryIndex"
    projection_type = "ALL"

    key_schema {
      attribute_name = "name"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "category"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "description"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "price"
      key_type       = "RANGE"
    }
    key_schema {
      attribute_name = "stock"
      key_type       = "RANGE"
    }
    key_schema {
      attribute_name = "imageUrl"
      key_type       = "RANGE"
    }
    key_schema {
      attribute_name = "createdAt"
      key_type       = "RANGE"
    }
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