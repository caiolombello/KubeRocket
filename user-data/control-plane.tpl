#cloud-config
write_files:
  - path: /etc/bottlerocket/settings.toml
    content: |
      [settings.kubernetes]
      api-server = "0.0.0.0:6443"
      cluster-name = "${cluster_name}"
      pod-infra-container-image = "registry.k8s.io/pause:3.9"
      cluster-dns-ip = "10.96.0.10"
      max-pods = 110
      cluster-domain = "cluster.local"
      node-ip = "$${KUBELET_NODE_IP}"
      pod-cidr = "${pod_network_cidr}"

      [settings.kubernetes.api-server]
      cert-sans = ["$${HOSTNAME}", "$${KUBELET_NODE_IP}"]
      enable-admission-plugins = ["NodeRestriction"]

      [settings.kubernetes.etcd]
      endpoints = [${etcd_endpoints}]
      initial-cluster = "${initial_cluster}"
      initial-cluster-state = "new"
      initial-cluster-token = "${cluster_name}-etcd"
      auto-compaction-retention = "8"
      quota-backend-bytes = 8589934592  # 8GB
      snapshot-count = 10000
      heartbeat-interval = 100
      election-timeout = 1000

      [settings.kubernetes.bootstrap-token]
      token = "${bootstrap_token}"
      description = "Bootstrap token for Kubernetes cluster"

      [settings.host-containers.admin]
      enabled = true
      superpowered = true
      user-data = jsonencode({
        ssh = {
          authorized-keys-command = "/opt/aws/bin/eic_run_authorized_keys %u %f"
          authorized-keys-command-user = "ec2-instance-connect"
        }
      })

      [settings.host-containers.control]
      enabled = true
      superpowered = true
      user-data = jsonencode({
        ssm = {
          region = "${aws_region}"
        }
      })

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

      [settings.bootstrap-containers.setup]
      source = "${setup_image}"
      mode = "once"
      essential = true
      user-data = "${setup_script}" 