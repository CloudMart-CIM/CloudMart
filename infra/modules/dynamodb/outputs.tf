output "products_table_name" {
  description = "DynamoDB products table name"
  value       = aws_dynamodb_table.products.name
}

output "products_table_arn" {
  description = "DynamoDB products table ARN"
  value       = aws_dynamodb_table.products.arn
}