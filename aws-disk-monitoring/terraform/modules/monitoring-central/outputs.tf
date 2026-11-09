output "controller_role_arn" {
  value = aws_iam_role.controller.arn
}

output "controller_role_name" {
  value = aws_iam_role.controller.name
}

output "controller_instance_profile" {
  value = aws_iam_instance_profile.controller.name
}

output "artifact_bucket_name" {
  value = aws_s3_bucket.artifacts.id
}

output "central_event_bus_arn" {
  value = aws_cloudwatch_event_bus.central.arn
}

output "alert_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
