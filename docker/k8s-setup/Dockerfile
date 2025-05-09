ARG K8S_VERSION=1.32.4
FROM public.ecr.aws/amazonlinux/amazonlinux:2 AS builder
ARG K8S_VERSION
ARG TARGETARCH

# Instala dependências básicas
RUN yum update -y && yum install -y \
    curl \
    tar \
    gzip \
    openssl

# Instala kubeadm, kubelet e kubectl
RUN curl -Lo /usr/local/bin/kubeadm \
      "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/${TARGETARCH}/kubeadm" && \
    curl -Lo /usr/local/bin/kubelet \
      "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/${TARGETARCH}/kubelet" && \
    curl -Lo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/${TARGETARCH}/kubectl" && \
    chmod +x /usr/local/bin/kubeadm /usr/local/bin/kubelet /usr/local/bin/kubectl

# Instala crictl
ARG CRICTL_VERSION=1.29.0
RUN curl -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRICTL_VERSION}/crictl-v${CRICTL_VERSION}-linux-${TARGETARCH}.tar.gz" | \
    tar -C /usr/local/bin -xz

# Instala runc
ARG RUNC_VERSION=1.1.12
RUN curl -L "https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${TARGETARCH}" \
    -o /usr/local/bin/runc && \
    chmod +x /usr/local/bin/runc

# Instala CNI plugins
ARG CNI_PLUGINS_VERSION=1.4.0
RUN mkdir -p /opt/cni/bin && \
    curl -L "https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-${TARGETARCH}-v${CNI_PLUGINS_VERSION}.tgz" | \
    tar -C /opt/cni/bin -xz

# Instala Helm
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod +x get_helm.sh && \
    VERIFY_CHECKSUM=true ./get_helm.sh

# Stage para AWS CLI v2
FROM public.ecr.aws/amazonlinux/amazonlinux:2 AS awscli
ARG TARGETARCH

# Instala dependências para AWS CLI v2
RUN yum update -y && yum install -y \
    unzip \
    && yum clean all

# Download e instalação do AWS CLI v2
RUN if [ "${TARGETARCH}" = "amd64" ]; then \
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"; \
    elif [ "${TARGETARCH}" = "arm64" ]; then \
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"; \
    fi && \
    unzip awscliv2.zip && \
    ./aws/install --bin-dir /aws-cli-bin/

# Imagem final
FROM public.ecr.aws/amazonlinux/amazonlinux:2
ARG TARGETARCH

# Instala dependências necessárias
RUN yum update -y && yum install -y \
    bash \
    etcd-client \
    jq \
    openssl \
    ethtool \
    socat \
    ebtables \
    iptables \
    iproute2 \
    && yum clean all

# Copia os binários da imagem builder
COPY --from=builder /usr/local/bin/kubeadm /usr/local/bin/kubeadm
COPY --from=builder /usr/local/bin/kubelet /usr/local/bin/kubelet
COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/kubectl
COPY --from=builder /usr/local/bin/crictl /usr/local/bin/crictl
COPY --from=builder /usr/local/bin/runc /usr/local/bin/runc
COPY --from=builder /usr/local/bin/helm /usr/local/bin/helm
COPY --from=builder /opt/cni/bin /opt/cni/bin

# Copia AWS CLI v2 da imagem awscli
COPY --from=awscli /usr/local/aws-cli/ /usr/local/aws-cli/
COPY --from=awscli /aws-cli-bin/ /usr/local/bin/

# Cria diretórios necessários
RUN mkdir -p \
    /etc/kubernetes/manifests \
    /etc/kubernetes/pki \
    /var/lib/kubelet \
    /var/lib/etcd && \
    chmod 750 /etc/kubernetes/pki

# Copia e configura o script de healthcheck
COPY healthcheck.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/healthcheck.sh

# Configura o healthcheck
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

# Verifica se as ferramentas foram instaladas corretamente
RUN kubeadm version && \
    kubectl version --client && \
    helm version && \
    aws --version && \
    crictl --version && \
    runc --version

WORKDIR /etc/kubernetes
ENTRYPOINT ["/bin/bash"] 