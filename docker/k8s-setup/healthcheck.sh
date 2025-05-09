#!/bin/bash

# Verifica se os binários essenciais estão disponíveis
for cmd in kubeadm kubectl kubelet aws crictl runc; do
    if ! command -v $cmd &> /dev/null; then
        echo "ERROR: $cmd not found"
        exit 1
    fi
done

# Verifica se os diretórios necessários existem e têm as permissões corretas
for dir in /etc/kubernetes/manifests /etc/kubernetes/pki /var/lib/kubelet /var/lib/etcd; do
    if [ ! -d "$dir" ]; then
        echo "ERROR: Directory $dir not found"
        exit 1
    fi
done

# Verifica se o diretório PKI tem as permissões corretas
if [ "$(stat -c %a /etc/kubernetes/pki)" != "750" ]; then
    echo "ERROR: Wrong permissions on /etc/kubernetes/pki"
    exit 1
fi

# Se chegou até aqui, está tudo OK
echo "All checks passed"
exit 0 