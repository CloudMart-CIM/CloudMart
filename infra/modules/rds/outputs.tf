output "rds_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.user.id
}

output "user_db_endpoint" {
  description = "RDS PostgreSQL endpoint for user-service"
  value       = aws_db_instance.user.address
}

output "user_db_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.user.port
}