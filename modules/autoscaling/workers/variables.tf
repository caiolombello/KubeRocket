variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
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
    use_spot_instances = optional(bool, false)
    spot_max_price     = optional(string)
    volume_iops        = optional(number, 3000)
    volume_throughput  = optional(number, 125)
    max_instance_lifetime = optional(number, 604800)
    enable_cluster_autoscaler = optional(bool, false)
  }))
}

variable "worker_security_group_id" {
  description = "ID of the security group for worker nodes"
  type        = string
}

variable "control_plane_endpoint" {
  description = "Endpoint of the Kubernetes API server"
  type        = string
}

variable "join_token" {
  description = "Token for joining the Kubernetes cluster"
  type        = string
  sensitive   = true
}

variable "discovery_token_ca_cert_hash" {
  description = "Hash of the Kubernetes CA certificate"
  type        = string
  sensitive   = true
}

variable "cluster_ca_certificate" {
  description = "The base64 encoded cluster CA certificate"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "user_data_template" {
  description = "Path to the user data template file"
  type        = string
}

variable "kubernetes_version" {
  description = "Version of Kubernetes to install"
  type        = string
}

variable "labels" {
  description = "Kubernetes labels to apply to the node"
  type        = map(string)
  default     = {}
}

variable "taints" {
  description = "Kubernetes taints to apply to the node"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

variable "node_draining_enabled" {
  description = "Enable automatic node draining"
  type        = bool
  default     = true
} 