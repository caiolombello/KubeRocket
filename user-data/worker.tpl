[settings.kubernetes]
api-server = "https://${control_plane_endpoint}"
cluster-name = "${cluster_name}"
pod-infra-container-image = "registry.k8s.io/pause:3.9"
cluster-dns-ip = "10.96.0.10"
max-pods = 110
cluster-domain = "cluster.local"
node-ip = "$${KUBELET_NODE_IP}"
cluster-token = "${join_token}"
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

[settings.host-containers.admin]
enabled = true
superpowered = true
user-data = { ssh = { authorized-keys-command = "/opt/aws/bin/eic_run_authorized_keys %u %f", authorized-keys-command-user = "ec2-instance-connect" } }

[settings.host-containers.control]
enabled = true
superpowered = true
user-data = { ssm = { region = "${aws_region}" } }

[settings.network]
hostname = "${hostname}"

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
sysctl = { 
    "net.ipv4.conf.all.forwarding" = "1", 
    "net.ipv4.ip_forward" = "1", 
    "net.bridge.bridge-nf-call-iptables" = "1",
    "net.ipv4.conf.all.send_redirects" = "0",
    "net.ipv4.conf.all.accept_redirects" = "0"
}

[settings.container-runtime]
max-container-log-size = "20Mi"
max-container-log-files = 3

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