output "order_events_queue_url" {
  description = "SQS order events queue URL"
  value       = aws_sqs_queue.order_events.url
}

output "order_events_queue_arn" {
  description = "SQS order events queue ARN"
  value       = aws_sqs_queue.order_events.arn
}