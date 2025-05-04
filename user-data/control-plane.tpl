[settings.kubernetes]
api-server = "https://$${HOSTNAME}:6443"
cluster-name = "${cluster_name}"
cluster-domain = "cluster.local"
pod-cidr = "${pod_network_cidr}"
service-cidr = "10.96.0.0/12"
authentication-mode = "tls"
bootstrap-token = "${bootstrap_token}"
standalone-mode = true
cluster-certificate = "${cluster_ca_cert}"
eviction-hard = { "memory.available" = "15%", "nodefs.available" = "10%", "nodefs.inodesFree" = "5%" }

[settings.network]
hostname = "$${HOSTNAME}"

[settings.host-containers.admin]
enabled = true
superpowered = true
user-data = '''
{
  "ssh": {
    "authorized-keys-command": "/opt/aws/bin/eic_run_authorized_keys %u %f",
    "authorized-keys-command-user": "ec2-instance-connect"
  }
}
'''

[settings.host-containers.control]
enabled = true
superpowered = true
user-data = '''
{
  "ssm": {
    "region": "${aws_region}"
  }
}
'''

[settings.updates]
metadata-base-url = "https://updates.bottlerocket.aws"
targets-base-url = "https://updates.bottlerocket.aws"
version-lock = false
ignore-waves = false

[settings.ntp]
time-servers = ["169.254.169.123"]

[settings.kernel]
lockdown = "integrity"
modules = ["br_netfilter", "overlay", "ip_tables", "iptable_nat", "iptable_filter"]
sysctl = { "net.ipv4.conf.all.forwarding" = "1", "net.ipv4.ip_forward" = "1", "net.bridge.bridge-nf-call-iptables" = "1", "net.ipv4.conf.all.send_redirects" = "0", "net.ipv4.conf.all.accept_redirects" = "0" }

[settings.container-runtime]
max-container-log-line-size = 20971520
enable-unprivileged-icmp = true
enable-unprivileged-ports = true 