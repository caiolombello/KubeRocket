# KubeRocket - Self-Managed Kubernetes with Bottlerocket

This Terraform configuration creates a self-managed Kubernetes cluster using AWS Bottlerocket OS. It provides a minimal setup with:

- VPC with public subnets
- Control plane node(s) running kubeadm
- Worker nodes that automatically join the cluster
- Cilium as CNI (Container Network Interface)
- Bottlerocket Update Operator for OS updates
- Support for both x86_64 (AMD64) and ARM64 (Graviton) architectures
- Automated SSH key generation and secure storage

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- AWS Secrets Manager access to store SSH keys

## Usage

1. Create a `terraform.tfvars` file with your configuration:

```hcl
aws_region          = "us-west-2"
cluster_name        = "kuberocket"
vpc_cidr           = "10.0.0.0/16"
public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
azs                = ["us-west-2a", "us-west-2b", "us-west-2c"]
instance_type      = "t3.medium"          # or "t4g.medium" for ARM64
control_plane_count = 1
worker_count       = 2
pod_network_cidr   = "10.244.0.0/16"
ssh_allowed_cidr_blocks = ["YOUR_IP/32"]  # Restrict SSH access
```

2. Initialize Terraform:
```bash
terraform init
```

3. Apply the configuration:
```bash
terraform apply
```

4. After the cluster is created, you can access it using the SSH key from AWS Secrets Manager:
```bash
# Get the SSH key from Secrets Manager
aws secretsmanager get-secret-value --secret-id $(terraform output -raw ssh_key_secret_id) --query 'SecretString' --output text | jq -r '.private_key' > cluster-key.pem
chmod 600 cluster-key.pem

# SSH into the control plane
ssh -i cluster-key.pem ec2-user@$(terraform output -raw control_plane_ip)
```

## Security Features

- SSH keys automatically generated and stored in AWS Secrets Manager
- SSH access restricted to specified CIDR blocks
- EBS volumes encrypted by default
- IMDSv2 required on all instances
- Security group rules limited to necessary ports
- Temporary SSH keys cleaned up after use

## Architecture

- VPC with public subnets in multiple AZs
- Control plane node(s) running kubeadm
- Worker nodes that automatically join the cluster
- Cilium for networking with kube-proxy replacement
- Security groups for control plane and worker communication
- Bottlerocket Update Operator for automated OS updates

## Instance Types

The configuration supports both x86_64 and ARM64 architectures. Here are some recommended instance types:

### AMD64 (x86_64)
- t3.medium/t3.large - General purpose, good for testing
- c6i.large/c6i.xlarge - Compute optimized
- m6i.large/m6i.xlarge - General purpose, production workloads

### ARM64 (Graviton)
- t4g.medium/t4g.large - General purpose, good for testing
- c7g.large/c7g.xlarge - Latest gen compute optimized
- m7g.large/m7g.xlarge - Latest gen general purpose

Choose the instance type based on your workload requirements and cost considerations. Graviton instances often provide better price/performance ratio.

## Modules

- `vpc`: Creates the VPC, subnets, and routing
- `autoscaling`: Reusable module for both control plane and worker nodes

## Network Features with Cilium

- Direct routing between pods across nodes
- kube-proxy replacement for better performance
- Network policy enforcement
- Load balancing for Kubernetes services
- VXLAN overlay networking

## Notes

- This is a minimal setup focused on the essential components
- The cluster uses public subnets for simplicity
- Consider adding:
  - Private subnets
  - More restrictive security groups
  - Load balancer for the control plane
  - Monitoring and logging
  - Additional Cilium features (service mesh, observability)
- When using ARM64:
  - Ensure all your container images have ARM64 support
  - Consider using multi-arch images when available
  - Test your applications for ARM64 compatibility

## Cleanup

To delete all resources:
```bash
terraform destroy
```

Note: This will also delete the SSH key from AWS Secrets Manager. 