resource "aws_secretsmanager_secret" "cluster_info" {
  name_prefix = "${var.cluster_name}-cluster-info-"
  description = "Kubernetes cluster information for ${var.cluster_name}"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "cluster_info" {
  secret_id = aws_secretsmanager_secret.cluster_info.id
  secret_string = jsonencode({
    status = "pending"
  })
} 