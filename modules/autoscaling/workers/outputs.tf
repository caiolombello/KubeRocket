output "asg_names" {
  description = "Names of the Auto Scaling Groups for worker nodes"
  value       = { for k, v in aws_autoscaling_group.worker : k => v.name }
}

output "launch_template_ids" {
  description = "IDs of the Launch Templates for worker nodes"
  value       = { for k, v in aws_launch_template.worker : k => v.id }
}

output "iam_role_arn" {
  description = "ARN of the IAM role for worker nodes"
  value       = aws_iam_role.worker.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for worker nodes"
  value       = aws_iam_role.worker.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile for worker nodes"
  value       = aws_iam_instance_profile.worker.arn
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile for worker nodes"
  value       = aws_iam_instance_profile.worker.name
}

output "worker_security_group_id" {
  description = "ID of the worker nodes security group"
  value       = var.worker_security_group_id
} 