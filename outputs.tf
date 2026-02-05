output "ec2_instance_id" {
  value = aws_instance.app.id
}

output "ec2_public_ip" {
  value = aws_instance.app.public_ip
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.sumo_checker.function_name
}

output "lambda_function_url" {
  value = aws_lambda_function_url.sumo_checker_url.function_url
}

