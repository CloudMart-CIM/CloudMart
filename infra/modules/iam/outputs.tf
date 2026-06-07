output "product_service_role_arn" {
  description = "ARN of the IAM role for the Product Service"
  value       = aws_iam_role.product_service.arn
}

output "order_service_role_arn" {
  description = "ARN of the IAM role for the Order Service"
  value       = aws_iam_role.order_service.arn
}

output "user_service_role_arn" {
  description = "ARN of the IAM role for the User Service"
  value       = aws_iam_role.user_service.arn
}

output "notification_service_role_arn" {
  description = "ARN of the IAM role for the Notification Service"
  value       = aws_iam_role.notification_service.arn
}
