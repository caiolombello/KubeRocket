variable "aws_region" {
  description = "AWS region"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "The aws_region must be a valid AWS region code."
  }
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "The cluster_name must consist of lower case alphanumeric characters and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)

  validation {
    condition     = length(var.public_subnets) > 0
    error_message = "At least one public subnet CIDR block must be provided."
  }
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)

  validation {
    condition     = length(var.azs) > 0
    error_message = "At least one availability zone must be provided."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string

  validation {
    condition     = can(regex("^[a-z][1-9][a-z]?\\.[\\da-z]+$", var.instance_type))
    error_message = "The instance_type must be a valid EC2 instance type."
  }
}

variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.control_plane_count > 0 && var.control_plane_count <= 5
    error_message = "The control_plane_count must be between 1 and 5."
  }
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 0
    error_message = "The worker_count must be greater than or equal to 0."
  }
}

variable "pod_network_cidr" {
  description = "CIDR block for pod network"
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_network_cidr, 0))
    error_message = "The pod_network_cidr must be a valid IPv4 CIDR block."
  }
}

variable "ssh_allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to SSH into nodes"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.ssh_allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All elements must be valid IPv4 CIDR blocks."
  }
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.private_subnets) == 0 || alltrue([for cidr in var.private_subnets : can(cidrhost(cidr, 0))])
    error_message = "All private subnet CIDR blocks must be valid IPv4 CIDR notation."
  }
}

variable "enable_nat_gateway" {
  description = "Should be true if you want to provision NAT Gateways for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Should be true if you want to provision a single shared NAT Gateway across all private subnets"
  type        = bool
  default     = false
}

variable "node_groups" {
  description = "Map of worker node group configurations"
  type = map(object({
    instance_type = string
    min_size      = number
    max_size      = number
    desired_size  = number
    disk_size     = number
    subnet_ids    = list(string)
    labels        = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
    instance_types = list(string)
    on_demand_base_capacity = number
    on_demand_percentage = number
    spot_allocation_strategy = string
    scaling_config = object({
      target_cpu_utilization    = number
      target_memory_utilization = number
      scale_in_cooldown        = number
      scale_out_cooldown       = number
    })
    update_config = object({
      max_unavailable_percentage = number
      pause_time                = string
    })
    kubelet_args = map(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.node_groups : v.min_size <= v.desired_size && v.desired_size <= v.max_size])
    error_message = "For each node group, min_size must be <= desired_size <= max_size."
  }

  validation {
    condition     = alltrue([
      for k, v in var.node_groups : (
        v.on_demand_percentage == null || 
        (v.on_demand_percentage >= 0 && v.on_demand_percentage <= 100)
      )
    ])
    error_message = "on_demand_percentage must be between 0 and 100."
  }

  validation {
    condition     = alltrue([
      for k, v in var.node_groups : (
        v.spot_allocation_strategy == null ||
        contains(["lowest-price", "capacity-optimized", "price-capacity-optimized"], v.spot_allocation_strategy)
      )
    ])
    error_message = "spot_allocation_strategy must be one of: lowest-price, capacity-optimized, price-capacity-optimized."
  }
}

variable "control_plane_accepts_workloads" {
  description = "Whether the control plane nodes should accept workloads (removes NoSchedule taint if true)"
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "Version of Bottlerocket OS to use for nodes"
  type        = string
  default     = "1.32.4"  # Updated to match the kubeadm image version

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "The kubernetes_version must be in the format 'X.Y.Z' (e.g. '1.32.4')."
  }
}

variable "instance_architecture" {
  description = "The architecture of the instances (arm64 or x86_64)"
  type        = string
  default     = "x86_64"
  
  validation {
    condition     = contains(["arm64", "x86_64"], var.instance_architecture)
    error_message = "The instance_architecture must be either arm64 or x86_64."
  }
}

variable "enable_prometheus_monitoring" {
  description = "Whether to enable Prometheus monitoring for the Bottlerocket Update Operator"
  type        = bool
  default     = false
}