output "asg_name" {
  description = "Name of the Auto Scaling Group for control plane nodes"
  value       = aws_autoscaling_group.control_plane.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling Group for control plane nodes"
  value       = aws_autoscaling_group.control_plane.arn
}

output "launch_template_id" {
  description = "ID of the Launch Template for control plane nodes"
  value       = aws_launch_template.control_plane.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role for control plane nodes"
  value       = aws_iam_role.control_plane.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for control plane nodes"
  value       = aws_iam_role.control_plane.name
}

output "instance_profile_arn" {
  description = "ARN of the IAM instance profile for control plane nodes"
  value       = aws_iam_instance_profile.control_plane.arn
}

output "instance_profile_name" {
  description = "Name of the IAM instance profile for control plane nodes"
  value       = aws_iam_instance_profile.control_plane.name
}

output "lb_dns_name" {
  description = "DNS name of the control plane load balancer"
  value       = aws_lb.control_plane.dns_name
}

output "bootstrap_token" {
  description = "The token workers can use to join the cluster"
  value       = random_string.bootstrap_token.result
  sensitive   = true
}

output "security_group_ids" {
  description = "List of security group IDs for control plane nodes"
  value       = var.security_group_ids
}

# Cluster endpoint
output "api_endpoint" {
  description = "The endpoint for the Kubernetes API server"
  value       = "https://${aws_lb.control_plane.dns_name}:6443"
}

# CA Certificate
output "cluster_ca_certificate" {
  description = "The cluster CA certificate in base64 format"
  value       = base64encode(tls_self_signed_cert.ca.cert_pem)
  sensitive   = true
}

# Discovery token CA cert hash
output "discovery_token_ca_cert_hash" {
  description = "The hash of the CA certificate for discovery"
  value       = "sha256:${sha256(base64decode(base64encode(tls_self_signed_cert.ca.cert_pem)))}"
  sensitive   = true
}

# Certificate Secret ARN
output "certificate_secret_arn" {
  description = "ARN of the secret containing cluster certificates"
  value       = aws_secretsmanager_secret.cluster_certs.arn
}

# Load Balancer DNS
output "load_balancer_dns" {
  description = "DNS name of the control plane load balancer"
  value       = aws_lb.control_plane.dns_name
} 