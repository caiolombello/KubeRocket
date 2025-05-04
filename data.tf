# Bottlerocket AMIs from SSM Parameter Store
data "aws_ssm_parameter" "bottlerocket_x86" {
  name = "/aws/service/bottlerocket/aws-k8s-${local.bottlerocket_ssm_version}/x86_64/latest/image_id"
}

data "aws_ssm_parameter" "bottlerocket_arm64" {
  name = "/aws/service/bottlerocket/aws-k8s-${local.bottlerocket_ssm_version}/arm64/latest/image_id"
}

# Get the control plane load balancer DNS name
data "aws_lb" "control_plane" {
  name = "${var.cluster_name}-cp"
  depends_on = [time_sleep.wait_for_control_plane]
}

# Get cluster information from Secrets Manager
data "aws_secretsmanager_secret_version" "cluster_info" {
  secret_id = aws_secretsmanager_secret.cluster_info.id
  depends_on = [time_sleep.wait_for_control_plane]
}

locals {
  cluster_info = jsondecode(data.aws_secretsmanager_secret_version.cluster_info.secret_string)
  
  # Common tags for all resources
  common_tags = {
    Environment = terraform.workspace
    Terraform   = "true"
    Project     = var.cluster_name
    ManagedBy   = "terraform"
  }

  # Bottlerocket version configuration - extract major.minor version
  bottlerocket_ssm_version = regex("^(\\d+\\.\\d+).*$", var.kubernetes_version)[0]
  
  # Instance architecture detection and AMI selection
  is_arm_instance = can(regex("^(a1|t4g|c6g|c7g|m6g|m7g|r6g|r7g)", var.instance_type))
  ami_id = coalesce(
    var.instance_architecture == "arm64" ? data.aws_ssm_parameter.bottlerocket_arm64.value : null,
    var.instance_architecture == "x86_64" ? data.aws_ssm_parameter.bottlerocket_x86.value : null,
    local.is_arm_instance ? data.aws_ssm_parameter.bottlerocket_arm64.value : data.aws_ssm_parameter.bottlerocket_x86.value
  )
} 