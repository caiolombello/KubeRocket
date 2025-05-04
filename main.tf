# Configure providers
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = terraform.workspace
      Terraform   = "true"
      Project     = var.cluster_name
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = module.control_plane.api_endpoint
    cluster_ca_certificate = base64decode(module.control_plane.cluster_ca_certificate)
    token                  = module.control_plane.bootstrap_token
  }
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  azs             = var.azs
  cluster_name    = var.cluster_name

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  tags = local.common_tags
}

# Generate bootstrap token for kubeadm
resource "random_string" "bootstrap_token" {
  length  = 6
  special = false
  upper   = false
}

# S3 bucket for etcd backups
resource "aws_s3_bucket" "etcd_backup" {
  bucket_prefix = "${var.cluster_name}-etcd-backup-"
  force_destroy = true

  tags = local.common_tags
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

# Control Plane Module
module "control_plane" {
  source = "./modules/autoscaling/control-plane"

  cluster_name     = var.cluster_name
  instance_type   = var.instance_type
  instance_count  = var.control_plane_count
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnet_ids
  security_group_ids = [aws_security_group.control_plane.id]
  key_name        = aws_key_pair.kubernetes.key_name
  kubernetes_version = var.kubernetes_version
  user_data_template = "${path.module}/user-data/control-plane.tpl"
  control_plane_accepts_workloads = var.control_plane_accepts_workloads
  
  setup_image     = "public.ecr.aws/l7c3q8m5/k8s-setup:1.32.4"
  scripts_path    = "${path.module}/user-data"
  aws_region      = var.aws_region
  etcd_backup_bucket = aws_s3_bucket.etcd_backup.id
  cluster_secret_id = aws_secretsmanager_secret.cluster_info.id

  tags = local.common_tags
}

# Wait for control plane instances to be ready
resource "time_sleep" "wait_for_control_plane" {
  depends_on = [module.control_plane]
  create_duration = "120s"
}

# Workers Module
module "workers" {
  source = "./modules/autoscaling/workers"

  cluster_name                 = var.cluster_name
  node_groups                 = {
    for name, group in var.node_groups : name => merge(group, {
      subnet_ids = [
        for cidr in group.subnet_ids : 
        element(module.vpc.public_subnet_ids, index(var.public_subnets, cidr))
      ]
    })
  }
  worker_security_group_id    = aws_security_group.worker.id
  control_plane_endpoint      = module.control_plane.api_endpoint
  join_token                  = module.control_plane.bootstrap_token
  discovery_token_ca_cert_hash = module.control_plane.discovery_token_ca_cert_hash
  cluster_ca_certificate      = module.control_plane.cluster_ca_certificate
  user_data_template          = "${path.module}/user-data/worker.tpl"
  kubernetes_version          = var.kubernetes_version
  labels                      = {}
  taints                      = []
  node_draining_enabled       = true

  tags = local.common_tags

  depends_on = [time_sleep.wait_for_control_plane]
}