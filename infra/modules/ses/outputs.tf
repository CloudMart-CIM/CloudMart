output "notification_service_secret_arn" {
  description = "Secrets Manager ARN for notification-service config"
  value       = aws_secretsmanager_secret.notification_service.arn
}

output "ses_verified_email" {
  description = "SES verified sender email"
  value       = var.ses_verified_email
}
