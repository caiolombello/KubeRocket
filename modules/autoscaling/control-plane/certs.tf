# Generate CA private key
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate CA certificate
resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "kubernetes-ca"
    organization = "Kubernetes"
  }

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature"
  ]
}

# Generate API Server private key
resource "tls_private_key" "apiserver" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate API Server certificate
resource "tls_cert_request" "apiserver" {
  private_key_pem = tls_private_key.apiserver.private_key_pem

  subject {
    common_name  = "kube-apiserver"
    organization = "system:masters"
  }

  dns_names = [
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster.local",
    "${var.cluster_name}-cp"
  ]

  ip_addresses = [
    "10.96.0.1",  # Kubernetes API Service IP (first IP in service-cidr)
    "127.0.0.1"   # Localhost
  ]
}

resource "tls_locally_signed_cert" "apiserver" {
  cert_request_pem   = tls_cert_request.apiserver.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 87600 # 10 years

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]
}

# Store certificates in AWS Secrets Manager
resource "aws_secretsmanager_secret" "cluster_certs" {
  name_prefix = "${var.cluster_name}-certificates-"
  force_overwrite_replica_secret = true
  recovery_window_in_days = 0  # Immediate deletion

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "cluster_certs" {
  secret_id = aws_secretsmanager_secret.cluster_certs.id
  secret_string = jsonencode({
    ca_cert          = base64encode(tls_self_signed_cert.ca.cert_pem)
    ca_key           = base64encode(tls_private_key.ca.private_key_pem)
    apiserver_cert   = base64encode(tls_locally_signed_cert.apiserver.cert_pem)
    apiserver_key    = base64encode(tls_private_key.apiserver.private_key_pem)
  })
} 