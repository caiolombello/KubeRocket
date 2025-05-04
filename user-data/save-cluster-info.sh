#!/usr/bin/env bash
set -euo pipefail

TOKEN=$(kubeadm token create --print-join-command)
HASH=$(echo $TOKEN | awk '{print $(NF)}')
KUBECONFIG=$(base64 -w0 /etc/kubernetes/admin.conf)

aws secretsmanager update-secret-version \
  --secret-id "${cluster_secret_id}" \
  --secret-string "{\"status\":\"ready\",\"join_token\":\"$${TOKEN}\",\"discovery_hash\":\"${HASH}\",\"kubeconfig\":\"${KUBECONFIG}\"}" \
  --region "${aws_region}" 