output "control_plane_ip" {
  description = "DNS name of the control plane load balancer"
  value       = data.aws_lb.control_plane.dns_name
}

output "control_plane_dns" {
  description = "The DNS name of the control plane load balancer"
  value       = data.aws_lb.control_plane.dns_name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "control_plane_endpoint" {
  description = "The endpoint for the Kubernetes control plane"
  value       = "https://${data.aws_lb.control_plane.dns_name}:6443"
}

output "bottlerocket_ami_id" {
  description = "Bottlerocket AMI ID being used"
  value       = local.ami_id
  sensitive   = true
}

output "cluster_info_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing cluster information"
  value       = aws_secretsmanager_secret.cluster_info.arn
}

output "ssh_key_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing the SSH key"
  value       = aws_secretsmanager_secret.ssh_key.arn
}

output "api_endpoint" {
  description = "The endpoint for the Kubernetes API server"
  value       = local.cluster_info.api_endpoint
}

output "cluster_ca_certificate" {
  description = "The cluster CA certificate in base64 format"
  value       = local.cluster_info.cluster_ca_certificate
  sensitive   = true
}

output "join_token" {
  description = "Token for joining worker nodes"
  value       = local.cluster_info.bootstrap_token
  sensitive   = true
}

output "discovery_token_ca_cert_hash" {
  description = "Hash of the CA certificate for discovery"
  value       = local.cluster_info.discovery_token_ca_cert_hash
  sensitive   = true
}

# Generate kubeconfig for external access
output "kubeconfig" {
  description = "Kubeconfig for accessing the cluster"
  sensitive   = true
  value = templatefile("${path.module}/templates/kubeconfig.tpl", {
    cluster_name     = var.cluster_name
    api_endpoint     = local.cluster_info.api_endpoint
    ca_certificate   = local.cluster_info.cluster_ca_certificate
    token           = local.cluster_info.bootstrap_token
  })
} 