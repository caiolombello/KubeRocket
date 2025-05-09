terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Bottlerocket AMIs from SSM Parameter Store
data "aws_ssm_parameter" "bottlerocket_x86" {
  name = "/aws/service/bottlerocket/aws-k8s-${local.bottlerocket_ssm_version}/x86_64/latest/image_id"
}

data "aws_ssm_parameter" "bottlerocket_arm64" {
  name = "/aws/service/bottlerocket/aws-k8s-${local.bottlerocket_ssm_version}/arm64/latest/image_id"
}

locals {
  # Bottlerocket version configuration
  bottlerocket_ssm_version = regex("^(\\d+\\.\\d+).*$", var.kubernetes_version)[0]
  
  # Instance architecture detection and AMI selection
  is_arm_instance = can(regex("^(a1|t4g|c6g|c7g|m6g|m7g|r6g|r7g)", var.instance_type))
  ami_id = local.is_arm_instance ? data.aws_ssm_parameter.bottlerocket_arm64.value : data.aws_ssm_parameter.bottlerocket_x86.value

  # Prepare the CA certificate - ensure it's properly base64 encoded without newlines
  cluster_ca_cert_base64 = replace(base64encode(tls_self_signed_cert.ca.cert_pem), "\n", "")

  # Pre-compute base64 encoded user-data for control container
  control_userdata = base64encode(jsonencode({
    ssm = {
      region = data.aws_region.current.name
    }
  }))

  # Pre-compute base64 encoded user-data for k8s-bootstrap container
  bootstrap_userdata = base64encode(<<-EOT
    #!/bin/bash
    set -e

    INTERNAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

    kubeadm init \
      --apiserver-advertise-address=$INTERNAL_IP \
      --pod-network-cidr=${var.pod_network_cidr} \
      --service-cidr=10.96.0.0/12 \
      --upload-certs \
      --node-name=$(hostname)

    aws secretsmanager put-secret-value \
      --secret-id ${var.cluster_secret_id} \
      --secret-string "$(cat /etc/kubernetes/admin.conf)" \
      --region ${data.aws_region.current.name}
  EOT
  )

  # Use the TOML template for user data
  control_plane_userdata = templatefile("${path.root}/templates/control-plane.toml", {
    hostname          = "control-plane-1"
    cluster_name      = var.cluster_name
    pod_network_cidr  = var.pod_network_cidr
    cluster_ca_cert   = local.cluster_ca_cert_base64
    aws_region        = data.aws_region.current.name
    setup_image       = var.setup_image
    cluster_secret_id = var.cluster_secret_id
    control_userdata  = local.control_userdata
    bootstrap_userdata = local.bootstrap_userdata
    kubernetes_version = var.kubernetes_version
    ssh = <<-EOT
[ssh]
authorized-keys-command = "/opt/aws/bin/eic_run_authorized_keys %u %f"
authorized-keys-command-user = "ec2-instance-connect"
EOT
    ssm_region = <<-EOT
[ssm]
region = "${data.aws_region.current.name}"
EOT
  })
}

# S3 bucket for etcd backups with enhanced configuration
resource "aws_s3_bucket" "etcd_backup" {
  bucket_prefix = "${var.cluster_name}-etcd-backup-"
  force_destroy = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-etcd-backup"
  })
}

resource "aws_s3_bucket_versioning" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Add lifecycle rules for backup retention
resource "aws_s3_bucket_lifecycle_configuration" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id

  rule {
    id     = "cleanup-old-backups"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    # Move backups to infrequent access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Delete backups after 90 days
    expiration {
      days = 90
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  # Keep only last 30 versions of each backup
  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {
      prefix = ""  # Apply to all objects
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Add bucket policy to enforce encryption
resource "aws_s3_bucket_policy" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyIncorrectEncryptionHeader"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.etcd_backup.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "AES256"
          }
        }
      },
      {
        Sid       = "DenyUnencryptedObjectUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.etcd_backup.arn}/*"
        Condition = {
          Null = {
            "s3:x-amz-server-side-encryption" = "true"
          }
        }
      }
    ]
  })
}

# Enhanced IAM policies for etcd backup with additional permissions
resource "aws_iam_role_policy" "etcd_backup" {
  name_prefix = "etcd-backup-"
  role        = aws_iam_role.control_plane.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:GetBucketLocation",
          "s3:ListBucketVersions",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          aws_s3_bucket.etcd_backup.arn,
          "${aws_s3_bucket.etcd_backup.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:ViaService": "s3.*.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Add EventBridge rule for automated backups
resource "aws_cloudwatch_event_rule" "etcd_backup" {
  name                = "${var.cluster_name}-etcd-backup"
  description         = "Trigger etcd backup on a schedule"
  schedule_expression = var.etcd_backup_schedule

  tags = var.tags
}

# Lambda function to invoke SSM Run Command
resource "aws_lambda_function" "etcd_backup" {
  filename      = "${path.module}/lambda/etcd_backup.zip"
  function_name = "${var.cluster_name}-etcd-backup"
  role          = aws_iam_role.lambda_ssm.arn
  handler       = "index.handler"
  runtime       = "python3.9"
  timeout       = 30

  environment {
    variables = {
      CLUSTER_NAME = var.cluster_name
    }
  }

  tags = var.tags
}

data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda/etcd_backup.zip"

  source {
    content = <<EOF
import boto3
import os

def handler(event, context):
    ssm = boto3.client('ssm')
    cluster_name = os.environ['CLUSTER_NAME']
    
    response = ssm.send_command(
        Targets=[{
            'Key': 'tag:kubernetes.io/role',
            'Values': ['control-plane']
        }],
        DocumentName='AWS-RunShellScript',
        Parameters={
            'commands': ['/etc/kubernetes/etcd-backup.sh'],
            'workingDirectory': ['/'],
            'executionTimeout': ['3600']
        },
        TimeoutSeconds=600,
        MaxConcurrency='1',
        MaxErrors='0'
    )
    return response
EOF
    filename = "index.py"
  }
}

# EventBridge target pointing to Lambda
resource "aws_cloudwatch_event_target" "etcd_backup" {
  rule      = aws_cloudwatch_event_rule.etcd_backup.name
  target_id = "TriggerEtcdBackup"
  arn       = aws_lambda_function.etcd_backup.arn
}

# Allow EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etcd_backup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.etcd_backup.arn
}

# IAM role for Lambda to invoke SSM
resource "aws_iam_role" "lambda_ssm" {
  name_prefix = "${var.cluster_name}-lambda-ssm-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "lambda_ssm" {
  name_prefix = "ssm-access-"
  role        = aws_iam_role.lambda_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
        Condition = {
          StringLike = {
            "aws:ResourceTag/kubernetes.io/role": "control-plane"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:*:document/AWS-RunShellScript"
        ]
      }
    ]
  })
}

# Allow Lambda to write logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Launch template for control plane nodes
resource "aws_launch_template" "control_plane" {
  name_prefix = "${var.cluster_name}-control-plane-${substr(sha256(local.control_plane_userdata), 0, 8)}-"
  description = "Launch template for Kubernetes control plane nodes"

  image_id      = local.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = var.security_group_ids

  user_data = base64encode(local.control_plane_userdata)

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 50
      volume_type = "gp3"
      encrypted   = true
      iops        = 3000
      throughput  = 125
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.control_plane.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                = "required"
    http_put_response_hop_limit = 2
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-control-plane"
    "kubernetes.io/role/control-plane" = "1"
  })

  update_default_version = true

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for control plane with improved leader election
resource "aws_autoscaling_group" "control_plane" {
  name_prefix = "${var.cluster_name}-control-plane-"

  desired_capacity = var.instance_count
  max_size         = var.instance_count
  min_size         = var.instance_count

  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.control_plane.id
    version = "$Default"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Improved rolling update strategy
  max_instance_lifetime = 604800  # 7 days
  
  dynamic "tag" {
    for_each = merge(
      var.tags,
      {
        Name                                        = "${var.cluster_name}-control-plane"
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        "kubernetes.io/role/control-plane"          = "1"
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
      min_healthy_percentage = 100
      instance_warmup       = 300
    }
    triggers = ["tag"]
  }
}

# IAM role for control plane nodes
resource "aws_iam_role" "control_plane" {
  name_prefix = "${var.cluster_name}-control-plane-"

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

# IAM role policies for control plane nodes
resource "aws_iam_role_policy_attachment" "control_plane_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.control_plane.name
}

resource "aws_iam_role_policy_attachment" "control_plane_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.control_plane.name
}

resource "aws_iam_role_policy_attachment" "control_plane_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.control_plane.name
}

resource "aws_iam_role_policy_attachment" "control_plane_AmazonEC2RoleforSSM" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  role       = aws_iam_role.control_plane.name
}

resource "aws_iam_role_policy_attachment" "control_plane_EC2InstanceConnect" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
  role       = aws_iam_role.control_plane.name
}

# Additional IAM policy for SSM Session Manager
resource "aws_iam_role_policy" "control_plane_ssm_session" {
  name_prefix = "ssm-session-"
  role        = aws_iam_role.control_plane.id

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

# IAM instance profile for control plane nodes
resource "aws_iam_instance_profile" "control_plane" {
  name_prefix = "${var.cluster_name}-control-plane-"
  role        = aws_iam_role.control_plane.name

  tags = var.tags
}

resource "aws_lb" "control_plane" {
  name               = "${var.cluster_name}-cp"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-control-plane"
  })
}

resource "aws_lb_target_group" "control_plane" {
  name_prefix = "k8scp-"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = var.vpc_id

  health_check {
    protocol            = "TCP"
    port                = 6443
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-control-plane"
  })
}

resource "aws_lb_listener" "control_plane" {
  load_balancer_arn = aws_lb.control_plane.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.control_plane.arn
  }
}

resource "aws_autoscaling_attachment" "control_plane" {
  autoscaling_group_name = aws_autoscaling_group.control_plane.name
  lb_target_group_arn   = aws_lb_target_group.control_plane.arn
}

resource "random_string" "bootstrap_token" {
  length  = 6
  special = false
  upper   = false
} 