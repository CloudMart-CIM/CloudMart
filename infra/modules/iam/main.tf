locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Team        = var.team
    Owner       = var.owner
    ManagedBy   = "terraform"
    Module      = "cloud-infrastructure-management"
  }

  oidc_url = replace(var.oidc_provider_url, "https://", "")
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# -------------------------
# Product Service — DynamoDB products table read/write
# -------------------------

data "aws_iam_policy_document" "product_service_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = [
        "system:serviceaccount:cloudmart-prod:product-service-sa",
        "system:serviceaccount:cloudmart-staging:product-service-sa"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "product_service" {
  name               = "${var.project_name}-product-service-role"
  assume_role_policy = data.aws_iam_policy_document.product_service_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-product-service-role"
  })
}

resource "aws_iam_policy" "product_service" {
  name        = "${var.project_name}-product-service-policy"
  description = "Read/write access to DynamoDB products table only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ProductTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_products_table}",
          "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.dynamodb_products_table}/index/*"
        ]
      },
      {
        Sid    = "AllowKMSForDynamoDB"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "product_service" {
  policy_arn = aws_iam_policy.product_service.arn
  role       = aws_iam_role.product_service.name
}

# -------------------------
# Order Service — SQS order events queue send/receive
# -------------------------

data "aws_iam_policy_document" "order_service_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = [
        "system:serviceaccount:cloudmart-prod:order-service-sa",
        "system:serviceaccount:cloudmart-staging:order-service-sa"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "order_service" {
  name               = "${var.project_name}-order-service-role"
  assume_role_policy = data.aws_iam_policy_document.order_service_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-order-service-role"
  })
}

resource "aws_iam_policy" "order_service" {
  name        = "${var.project_name}-order-service-policy"
  description = "Send/receive access to SQS order events queue only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OrderQueueAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_order_events_queue_arn
      },
      {
        Sid      = "AllowKMSForSQS"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt", "kms:DescribeKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "order_service" {
  policy_arn = aws_iam_policy.order_service.arn
  role       = aws_iam_role.order_service.name
}

# -------------------------
# Notification Service — SQS receive/delete + SES send email
# -------------------------

data "aws_iam_policy_document" "notification_service_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = [
        "system:serviceaccount:cloudmart-prod:notification-service-sa",
        "system:serviceaccount:cloudmart-staging:notification-service-sa"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "notification_service" {
  name               = "${var.project_name}-notification-service-role"
  assume_role_policy = data.aws_iam_policy_document.notification_service_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-notification-service-role"
  })
}

resource "aws_iam_policy" "notification_service" {
  name        = "${var.project_name}-notification-service-policy"
  description = "Receive/delete from SQS order events queue and send email via SES only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OrderQueueConsumerAccess"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_order_events_queue_arn
      },
      {
        Sid    = "SESSendEmailAccess"
        Effect = "Allow"
        Action = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/${var.ses_verified_email}"
      },
      {
        Sid      = "AllowKMSForSQS"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "notification_service" {
  policy_arn = aws_iam_policy.notification_service.arn
  role       = aws_iam_role.notification_service.name
}

# -------------------------
# User Service — Secrets Manager read credentials only
# -------------------------

data "aws_iam_policy_document" "user_service_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = [
        "system:serviceaccount:cloudmart-prod:user-service-sa",
        "system:serviceaccount:cloudmart-staging:user-service-sa"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "user_service" {
  name               = "${var.project_name}-user-service-role"
  assume_role_policy = data.aws_iam_policy_document.user_service_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-user-service-role"
  })
}

resource "aws_iam_policy" "user_service" {
  name        = "${var.project_name}-user-service-policy"
  description = "Read-only access to user-service DB and JWT secrets in Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadUserServiceSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [
          var.user_service_db_secret_arn,
          var.user_service_jwt_secret_arn
        ]
      },
      {
        Sid      = "AllowKMSDecryptForSecretsManager"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "user_service" {
  policy_arn = aws_iam_policy.user_service.arn
  role       = aws_iam_role.user_service.name
}
