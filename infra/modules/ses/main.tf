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
