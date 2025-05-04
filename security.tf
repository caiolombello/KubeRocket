# Generate SSH key pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store private key in AWS Secrets Manager
resource "aws_secretsmanager_secret" "ssh_key" {
  name_prefix = "${var.cluster_name}-ssh-key-"
  description = "SSH private key for Kubernetes cluster nodes"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "ssh_key" {
  secret_id = aws_secretsmanager_secret.ssh_key.id
  secret_string = jsonencode({
    private_key = tls_private_key.ssh.private_key_pem
    public_key  = tls_private_key.ssh.public_key_openssh
  })
}

# Create EC2 key pair
resource "aws_key_pair" "kubernetes" {
  key_name_prefix = "${var.cluster_name}-"
  public_key      = tls_private_key.ssh.public_key_openssh

  tags = local.common_tags
}

# Create a temporary file for SSH key (used by external data sources)
resource "local_sensitive_file" "ssh_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/temp/${var.cluster_name}-ssh-key"
  file_permission = "0600"
}

# Create directory for temporary files
resource "local_file" "temp_dir" {
  content  = ""
  filename = "${path.module}/temp/.keep"

  provisioner "local-exec" {
    command = "chmod 700 ${path.module}/temp"
  }
}

# Security Groups
resource "aws_security_group" "control_plane" {
  name_prefix = "${var.cluster_name}-control-plane-"
  description = "Security group for Kubernetes control plane"
  vpc_id      = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Kubernetes API server"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr_blocks
    description = "SSH access"
  }

  # Cilium VXLAN port
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
    description = "Cilium VXLAN"
  }

  # Cilium health checks
  ingress {
    from_port   = 4240
    to_port     = 4240
    protocol    = "tcp"
    self        = true
    description = "Cilium health checks"
  }

  # etcd server client API
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
    description = "etcd server client API"
  }

  # Kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
    description = "Kubelet API"
  }

  # kube-scheduler
  ingress {
    from_port   = 10251
    to_port     = 10251
    protocol    = "tcp"
    self        = true
    description = "kube-scheduler"
  }

  # kube-controller-manager
  ingress {
    from_port   = 10252
    to_port     = 10252
    protocol    = "tcp"
    self        = true
    description = "kube-controller-manager"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-control-plane"
  })
}

resource "aws_security_group" "worker" {
  name_prefix = "${var.cluster_name}-worker-"
  description = "Security group for Kubernetes workers"
  vpc_id      = module.vpc.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr_blocks
    description = "SSH access"
  }

  # Cilium VXLAN port
  ingress {
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
    description = "Cilium VXLAN"
  }

  # Cilium health checks
  ingress {
    from_port   = 4240
    to_port     = 4240
    protocol    = "tcp"
    self        = true
    description = "Cilium health checks"
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.control_plane.id]
    description     = "Allow all traffic from control plane"
  }

  # Kubelet API
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
    description = "Kubelet API"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-worker"
  })
} 