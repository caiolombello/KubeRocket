terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_region" "current" {}

# Bottlerocket AMIs from SSM Parameter Store
data "aws_ssm_parameter" "bottlerocket_x86" {
  name = "/aws/service/bottlerocket/aws-k8s-${local.bottlerocket_ssm_version}/x86_64/latest/image_id"
}

data "aws_ssm_parameter" "bottlerocket_arm64" {
  name = "/aws/service/bottlerocket/aws-k8s-${local.bottlerocket_ssm_version}/arm64/latest/image_id"
}

locals {
  node_groups = var.node_groups
  # Bottlerocket version configuration
  bottlerocket_ssm_version = regex("^(\\d+\\.\\d+).*$", var.kubernetes_version)[0]
  
  # Instance architecture detection and AMI selection for each node group
  node_group_architectures = {
    for name, group in var.node_groups : name => {
      is_arm_instance = can(regex("^(a1|t4g|c6g|c7g|m6g|m7g|r6g|r7g)", group.instance_type))
      ami_id = can(regex("^(a1|t4g|c6g|c7g|m6g|m7g|r6g|r7g)", group.instance_type)) ? data.aws_ssm_parameter.bottlerocket_arm64.value : data.aws_ssm_parameter.bottlerocket_x86.value
    }
  }
  
  # Processar labels e taints para user-data
  node_group_settings = {
    for name, group in var.node_groups : name => {
      labels = join(",", [for k, v in group.labels : "${k}=${v}"])
      taints = join(",", [for t in group.taints : "${t.key}=${t.value}:${t.effect}"])
    }
  }
}

# IAM role for worker nodes
resource "aws_iam_role" "worker" {
  name_prefix = "${var.cluster_name}-worker-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Additional IAM policy for node draining
resource "aws_iam_role_policy" "node_draining" {
  name_prefix = "node-draining-"
  role        = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CompleteLifecycleAction",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLifecycleHooks",
          "autoscaling:RecordLifecycleActionHeartbeat"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role policies for worker nodes
resource "aws_iam_role_policy_attachment" "worker_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "worker_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "worker_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "worker_AmazonEC2RoleforSSM" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  role       = aws_iam_role.worker.name
}

resource "aws_iam_role_policy_attachment" "worker_EC2InstanceConnect" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  role       = aws_iam_role.worker.name
}

# Additional IAM policy for SSM Session Manager
resource "aws_iam_role_policy" "worker_ssm_session" {
  name_prefix = "ssm-session-"
  role        = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Launch template for each node group
resource "aws_launch_template" "worker" {
  for_each = local.node_groups

  name_prefix = "${var.cluster_name}-${each.key}-"
  description = "Launch template for ${var.cluster_name} ${each.key} worker nodes"

  image_id = local.node_group_architectures[each.key].ami_id
  instance_type = each.value.instance_type

  vpc_security_group_ids = [var.worker_security_group_id]

  user_data = base64encode(templatefile(var.user_data_template, {
    cluster_name     = var.cluster_name
    api_server_addr  = var.control_plane_endpoint
    join_token       = var.join_token
    cluster_ca_certificate = var.cluster_ca_certificate
    discovery_token_ca_cert_hash = var.discovery_token_ca_cert_hash
    kubernetes_version = var.kubernetes_version
    aws_region      = data.aws_region.current.name
    labels          = var.labels
    taints          = var.taints
    node_draining_enabled = var.node_draining_enabled
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = each.value.disk_size
      volume_type = "gp3"
      encrypted   = true
      iops        = lookup(each.value, "volume_iops", 3000)
      throughput  = lookup(each.value, "volume_throughput", 125)
    }
  }

  dynamic "instance_market_options" {
    for_each = lookup(each.value, "use_spot_instances", false) ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price = lookup(each.value, "spot_max_price", null)
        spot_instance_type = "persistent"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.worker.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${each.key}-worker"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# IAM instance profile for worker nodes
resource "aws_iam_instance_profile" "worker" {
  name_prefix = "${var.cluster_name}-worker-"
  role        = aws_iam_role.worker.name

  tags = var.tags
}

# Auto Scaling Group lifecycle hook for node draining
resource "aws_autoscaling_lifecycle_hook" "worker_drain" {
  for_each = local.node_groups

  name                    = "${var.cluster_name}-${each.key}-drain"
  autoscaling_group_name  = aws_autoscaling_group.worker[each.key].name
  lifecycle_transition    = "autoscaling:EC2_INSTANCE_TERMINATING"
  heartbeat_timeout      = 300
  default_result         = "CONTINUE"
}

# Auto Scaling Group for each node group
resource "aws_autoscaling_group" "worker" {
  for_each = local.node_groups

  name_prefix = "${var.cluster_name}-${each.key}-"
  
  min_size = each.value.min_size
  max_size = each.value.max_size
  desired_capacity = each.value.desired_size
  
  vpc_zone_identifier = each.value.subnet_ids

  launch_template {
    id      = aws_launch_template.worker[each.key].id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Improved rolling update strategy
  max_instance_lifetime = lookup(each.value, "max_instance_lifetime", 604800)  # 7 days default
  
  dynamic "tag" {
    for_each = merge(
      var.tags,
      {
        Name = "${var.cluster_name}-${each.key}-worker"
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        "k8s.io/cluster-autoscaler/enabled" = lookup(each.value, "enable_cluster_autoscaler", "false")
        "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
      }
    )
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes       = [desired_capacity]
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup       = 300
    }
  }
} 