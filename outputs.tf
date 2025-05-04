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

output "kubeconfig" {
  description = "Kubeconfig for the cluster"
  value       = local.cluster_info.kubeconfig
  sensitive   = true
}

output "join_token" {
  description = "Token for joining worker nodes"
  value       = local.cluster_info.join_token
  sensitive   = true
}

output "join_hash" {
  description = "Discovery token CA cert hash for joining worker nodes"
  value       = local.cluster_info.discovery_token_ca_cert_hash
  sensitive   = true
} 