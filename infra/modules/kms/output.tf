output "kms_key_arn" {
  description = "CloudMart KMS key ARN"
  value       = aws_kms_key.cloudmart.arn
}