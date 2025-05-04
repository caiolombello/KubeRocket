#!/usr/bin/env bash
set -euo pipefail

# Função para esperar o API server ficar disponível
wait_for_apiserver() {
    echo "Waiting for API server to become ready..."
    until kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes &>/dev/null; do
        sleep 5
    done
    echo "API server is ready"
}

# Função para backup do etcd
backup_etcd() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="/var/lib/etcd/backup/etcd-snapshot-$timestamp.db"
    
    echo "Creating etcd backup..."
    mkdir -p /var/lib/etcd/backup
    ETCDCTL_API=3 etcdctl snapshot save "$backup_file"
    
    echo "Uploading backup to S3..."
    aws s3 cp "$backup_file" "s3://${etcd_backup_bucket}/"
}

# Inicializar o cluster
echo "Initializing Kubernetes cluster..."
kubeadm init \
    --pod-network-cidr="${pod_network_cidr}" \
    --token="${bootstrap_token}" \
    --token-ttl=24h \
    --apiserver-cert-extra-sans="${node_ip}" \
    --node-name="${hostname}" \
    --skip-phases=addon/kube-proxy \
    --control-plane-endpoint="${cluster_name}-cp:6443"

# Esperar o API server ficar disponível
wait_for_apiserver

# Instalar Cilium
echo "Installing Cilium..."
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
    --namespace=kube-system \
    --set=kubeProxyReplacement=strict \
    --set=k8sServiceHost="${node_ip}" \
    --set=k8sServicePort=6443 \
    --set=encryption.enabled=true \
    --set=hubble.enabled=true \
    --set=hubble.metrics.enabled=true

# Esperar o Cilium ficar pronto
echo "Waiting for Cilium pods to be ready..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system wait --for=condition=ready pod -l k8s-app=cilium --timeout=300s

# Fazer backup do etcd
backup_etcd

# Remover taints se necessário
if [ "${control_plane_accepts_workloads}" = "true" ]; then
    echo "Removing control plane taints..."
    kubectl --kubeconfig=/etc/kubernetes/admin.conf taint nodes "${hostname}" node-role.kubernetes.io/control-plane:NoSchedule- || true
    kubectl --kubeconfig=/etc/kubernetes/admin.conf taint nodes "${hostname}" node-role.kubernetes.io/master:NoSchedule- || true
fi

# Salvar informações do cluster no Secrets Manager
echo "Saving cluster information..."
join_command=$(kubeadm token create --print-join-command)
discovery_token_ca_cert_hash=$(echo "$join_command" | awk '{print $(NF)}') # Extract the hash from the join command
# Extract CA cert and token from kubeconfig
ca_cert=$(grep 'certificate-authority-data:' /etc/kubernetes/admin.conf | awk '{print $2}')
user_token=$(grep 'token:' /etc/kubernetes/admin.conf | awk '{print $2}')
kubeconfig_b64=$(base64 -w0 /etc/kubernetes/admin.conf)

# Construct the JSON payload
secret_json=$(cat <<EOF
{
  "status": "ready",
  "join_token": "$${bootstrap_token}", 
  "discovery_token_ca_cert_hash": "$${discovery_token_ca_cert_hash}",
  "kubeconfig": "$${kubeconfig_b64}",
  "cluster_ca_certificate": "$${ca_cert}",
  "token": "$${user_token}"
}
EOF
)

aws secretsmanager update-secret-version \
    --secret-id "${cluster_secret_id}" \
    --secret-string "$secret_json" \
    --region "${aws_region}"

echo "Kubernetes setup completed successfully" 