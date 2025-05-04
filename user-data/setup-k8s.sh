#!/bin/bash
set -euo pipefail

# Function to calculate CA cert hash
calculate_ca_hash() {
    openssl x509 -in /etc/kubernetes/pki/ca.crt -pubkey \
        | openssl rsa -pubin -outform der 2>/dev/null \
        | sha256sum | awk '{print "sha256:" $1}'
}

# Function to generate a valid kubeadm token
generate_token() {
    # Generate a token that matches [a-z0-9]{6}\.[a-z0-9]{16}
    local token_id=$(tr -dc 'a-z0-9' < /dev/urandom | fold -w 6 | head -n 1)
    local token_secret=$(tr -dc 'a-z0-9' < /dev/urandom | fold -w 16 | head -n 1)
    echo "$${token_id}.$${token_secret}"
}

# Function to store cluster info in AWS Secrets Manager
store_cluster_info() {
    local token="$1"
    local ca_hash="$2"
    local ca_cert=$(base64 -w 0 /etc/kubernetes/pki/ca.crt)
    local admin_conf=$(base64 -w 0 /etc/kubernetes/admin.conf)

    # Create JSON payload
    local payload=$(cat <<EOF
{
    "token": "$${token}",
    "discovery_token_ca_cert_hash": "$${ca_hash}",
    "cluster_ca_certificate": "$${ca_cert}",
    "kubeconfig": "$${admin_conf}",
    "status": "ready"
}
EOF
)

    # Store in AWS Secrets Manager
    aws secretsmanager put-secret-value \
        --secret-id "${cluster_secret_id}" \
        --secret-string "$payload" \
        --region "${aws_region}"
}

# Main initialization logic
main() {
    # Generate secure token
    TOKEN=$(generate_token)

    # Initialize control plane
    kubeadm init \
        --token "$${TOKEN}" \
        --token-ttl 0 \
        --pod-network-cidr "${pod_network_cidr}" \
        --node-name "${hostname}" \
        --upload-certs \
        --control-plane-endpoint "${cluster_name}-cp:6443"

    # Calculate CA hash
    CA_HASH=$(calculate_ca_hash)

    # Store cluster information
    store_cluster_info "$${TOKEN}" "$${CA_HASH}"

    # Configure kubelet for control plane
    if [[ "${control_plane_accepts_workloads}" == "false" ]]; then
        kubectl --kubeconfig /etc/kubernetes/admin.conf taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule
    fi

    # Install Cilium CNI
    helm --kubeconfig /etc/kubernetes/admin.conf repo add cilium https://helm.cilium.io/
    helm --kubeconfig /etc/kubernetes/admin.conf install cilium cilium/cilium \
        --namespace kube-system \
        --set encryption.enabled=true \
        --set encryption.type=wireguard

    # Configure etcd backup
    cat > /etc/kubernetes/etcd-backup.sh <<EOF
#!/bin/bash
set -euo pipefail

TIMESTAMP=\$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="/tmp/etcd-backup-\$${TIMESTAMP}.db"
S3_PATH="s3://${etcd_backup_bucket}/backups/\$${TIMESTAMP}/snapshot.db"

# Create backup
ETCDCTL_API=3 etcdctl snapshot save "\$${BACKUP_PATH}" \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key

# Upload to S3
aws s3 cp "\$${BACKUP_PATH}" "\$${S3_PATH}"

# Cleanup
rm -f "\$${BACKUP_PATH}"
EOF

    chmod +x /etc/kubernetes/etcd-backup.sh

    # Add backup cron job
    echo "0 2 * * * root /etc/kubernetes/etcd-backup.sh" > /etc/cron.d/etcd-backup
}

# Execute main function
main 