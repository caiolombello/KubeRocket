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
require-each-update = true

[settings.ntp]
time-servers = ["169.254.169.123"]

[settings.kernel]
lockdown = "integrity"
modules = ["br_netfilter", "overlay", "ip_tables", "iptable_nat", "iptable_filter"]
sysctl = { "net.ipv4.conf.all.forwarding" = "1", "net.ipv4.ip_forward" = "1", "net.bridge.bridge-nf-call-iptables" = "1", "net.ipv4.conf.all.send_redirects" = "0", "net.ipv4.conf.all.accept_redirects" = "0" }

[settings.container-runtime]
max-container-log-line-size = "20Mi"

[settings.kubernetes]
authentication-mode = "tls"

[settings.bootstrap-containers.setup]
source = "${setup_image}"
mode = "once"
essential = true
user-data = "${setup_script}" 