[settings.kubernetes]
api-server = "${api_server_addr}"
cluster-name = "${cluster_name}"
authentication-mode = "tls"
cluster-certificate = "${cluster_ca_certificate}"
bootstrap-token = "${join_token}"
pod-infra-container-image = "registry.k8s.io/pause:3.9"
cluster-dns-ip = "10.96.0.10"
max-pods = 110
cluster-domain = "cluster.local"
node-ip = "$${KUBELET_NODE_IP}"
cluster-token-ca-cert-hash = "${discovery_token_ca_cert_hash}"

[settings.kubernetes.node-labels]
${join(",", [for key, value in labels : "${key}=${value}"])}

[settings.kubernetes.node-taints]
${join(",", [for taint in taints : "${taint.key}=${taint.value}:${taint.effect}"])}

[settings.kubernetes.eviction-hard]
memory.available = "5%"
nodefs.available = "10%"
nodefs.inodesFree = "5%"

[settings.kubernetes.system-reserved]
cpu = "100m"
memory = "100Mi"
ephemeral-storage = "1Gi"

[settings.kubernetes.kube-reserved]
cpu = "100m"
memory = "100Mi"
ephemeral-storage = "1Gi"

[settings.network]
hostname = "$${HOSTNAME}"

[settings.updates]
metadata-base-url = "https://updates.bottlerocket.aws"
targets-base-url = "https://updates.bottlerocket.aws"
version-lock = false
ignore-waves = false
require-each-update = true

[settings.ntp]
time-servers = ["169.254.169.123"]

[settings.kernel]
lockdown = "integrity"
modules = ["br_netfilter", "overlay", "ip_tables", "iptable_nat", "iptable_filter"]
sysctl = { "net.ipv4.conf.all.forwarding" = "1", "net.ipv4.ip_forward" = "1", "net.bridge.bridge-nf-call-iptables" = "1" }

[settings.container-runtime]
max-container-log-line-size = 20971520
enable-unprivileged-icmp = true
enable-unprivileged-ports = true

[settings.bootstrap-containers.kubeadm-join]
source = "docker.io/caiolombello/kubeadmin:${kubernetes_version}"
mode = "once"
essential = true
command = ["/usr/bin/kubeadm"]
args = [
    "join",
    "${api_server_addr}",
    "--token",
    "${join_token}",
    "--discovery-token-ca-cert-hash",
    "${discovery_token_ca_cert_hash}",
    "--node-name=$${HOSTNAME}"
]

%{ if node_draining_enabled }
[settings.bootstrap-containers.node-drainer]
source = "docker.io/caiolombello/kubeadmin:${kubernetes_version}"
mode = "always"
essential = false
user = "root"
command = ["/bin/bash", "-c", "while true; do if [ -f /var/lib/bottlerocket/lifecycle-hook ]; then kubectl --kubeconfig=/etc/kubernetes/kubelet.conf drain --ignore-daemonsets --delete-emptydir-data --force $${HOSTNAME} && aws autoscaling complete-lifecycle-action --lifecycle-hook-name ${cluster_name}-drain --auto-scaling-group-name ${cluster_name}-workers --lifecycle-action-result CONTINUE --instance-id $${INSTANCE_ID} --region ${aws_region}; fi; sleep 5; done"]

[settings.bootstrap-containers.spot-handler]
source = "docker.io/caiolombello/kubeadmin:${kubernetes_version}"
mode = "always"
essential = false
user = "root"
command = ["/bin/bash", "-c", "while true; do TOKEN=$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600') && if curl -H \"X-aws-ec2-metadata-token: $TOKEN\" -s http://169.254.169.254/latest/meta-data/spot/instance-action; then kubectl --kubeconfig=/etc/kubernetes/kubelet.conf drain --ignore-daemonsets --delete-emptydir-data --force $${HOSTNAME}; fi; sleep 5; done"]
%{ endif } 