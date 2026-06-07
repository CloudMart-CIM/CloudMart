output "user_service_db_secret_arn" {
  description = "Secrets Manager ARN for user-service DB credentials"
  value       = aws_secretsmanager_secret.user_service_db.arn
}

output "user_service_jwt_secret_arn" {
  description = "Secrets Manager ARN for user-service JWT secret"
  value       = aws_secretsmanager_secret.user_service_jwt.arn
}

output "notification_service_secret_arn" {
  description = "Secrets Manager ARN for notification-service config"
  value       = aws_secretsmanager_secret.notification_service.arn
}