variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for control plane nodes"
  type        = string
}

variable "instance_count" {
  description = "Number of control plane instances"
  type        = number
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the control plane nodes"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the control plane nodes"
  type        = list(string)
}

variable "key_name" {
  description = "Name of the EC2 key pair to use for SSH access"
  type        = string
}

variable "user_data_template" {
  description = "Path to the user data template file"
  type        = string
}

variable "kubernetes_version" {
  description = "Version of Kubernetes to install"
  type        = string
}

variable "pod_network_cidr" {
  description = "CIDR block for pod network"
  type        = string
  default     = "10.244.0.0/16"
}

variable "root_volume_size" {
  description = "Size of the root volume in GB"
  type        = number
  default     = 50
}

variable "control_plane_accepts_workloads" {
  description = "Whether the control plane nodes should accept workloads"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "scripts_path" {
  description = "Path to the scripts directory"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "setup_image" {
  description = "Docker image for Kubernetes setup container"
  type        = string
  default     = "public.ecr.aws/l7c3q8m5/k8s-setup:1.32.4"
}

variable "etcd_backup_bucket" {
  description = "S3 bucket for etcd backups"
  type        = string
}

variable "cluster_secret_id" {
  description = "ID of the Secrets Manager secret for cluster information"
  type        = string
}

variable "etcd_backup_schedule" {
  description = "Schedule expression for automated etcd backups (e.g., 'cron(0 2 * * ? *)')"
  type        = string
  default     = "cron(0 2 * * ? *)"  # Default to 2 AM UTC daily
}

variable "backup_alarm_sns_topics" {
  description = "List of SNS topic ARNs to notify when backup fails"
  type        = list(string)
  default     = []
} 