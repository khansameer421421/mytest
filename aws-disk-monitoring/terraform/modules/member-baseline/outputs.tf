output "ansible_role_arn" {
  value = aws_iam_role.ansible.arn
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.instance.name
}

output "events_forward_role_arn" {
  value = aws_iam_role.events_forward.arn
}
