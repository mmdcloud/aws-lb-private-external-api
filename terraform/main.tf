# =============================================================================
# AWS Application Load Balancer -> AWS Site-to-Site VPN -> GCP HA VPN ->
# GCP Private External API Compute Instances (IP Target Group)
# =============================================================================

# -----------------------------------------------------------------------------
# Tunnel topology & Cryptographic PSK Generation
# -----------------------------------------------------------------------------
locals {
  vpn_tunnels = {
    "0-1" = { conn = "0", aws_tunnel = 1, gcp_interface = 0, peer_interface = 0 }
    "0-2" = { conn = "0", aws_tunnel = 2, gcp_interface = 0, peer_interface = 1 }
    "1-1" = { conn = "1", aws_tunnel = 1, gcp_interface = 1, peer_interface = 2 }
    "1-2" = { conn = "1", aws_tunnel = 2, gcp_interface = 1, peer_interface = 3 }
  }

  aws_vpn_connections = {
    "0" = aws_vpn_connection.vpn_conn_0
    "1" = aws_vpn_connection.vpn_conn_1
  }
}

# One PSK per tunnel. AWS rejects PSKs starting with "0", so prefix with "vpn_".
resource "random_password" "psk" {
  for_each = local.vpn_tunnels
  length   = 32
  special  = false
}

locals {
  psk = { for k, v in random_password.psk : k => "vpn_${v.result}" }
}

# -----------------------------------------------------------------------------
# AWS: VPC, Virtual Private Gateway, Route Propagation, Customer Gateways, VPN
# -----------------------------------------------------------------------------
module "aws_vpc" {
  source                  = "./modules/aws/vpc"
  vpc_name                = "${var.environment}-aws-vpc"
  vpc_cidr                = var.aws_vpc_cidr
  azs                     = var.azs
  public_subnets          = var.public_subnets
  private_subnets         = var.private_subnets
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false
  tags                    = var.tags
}

resource "aws_vpn_gateway" "vpn_gw" {
  vpc_id          = module.aws_vpc.vpc_id
  amazon_side_asn = var.aws_bgp_asn

  tags = merge(var.tags, {
    Name = "${var.environment}-aws-vgw-gcp"
  })
}

# Propagate BGP learned routes into public route tables (where ALB sits) and private route tables
resource "aws_vpn_gateway_route_propagation" "public" {
  count          = length(module.aws_vpc.public_route_table_ids)
  vpn_gateway_id = aws_vpn_gateway.vpn_gw.id
  route_table_id = module.aws_vpc.public_route_table_ids[count.index]
}

resource "aws_vpn_gateway_route_propagation" "private" {
  count          = length(module.aws_vpc.private_route_table_ids)
  vpn_gateway_id = aws_vpn_gateway.vpn_gw.id
  route_table_id = module.aws_vpc.private_route_table_ids[count.index]
}

resource "aws_customer_gateway" "gcp_cgw_0" {
  bgp_asn    = var.gcp_bgp_asn
  ip_address = google_compute_ha_vpn_gateway.ha_gateway.vpn_interfaces[0].ip_address
  type       = "ipsec.1"

  tags = merge(var.tags, {
    Name = "${var.environment}-gcp-customer-gw-0"
  })
}

resource "aws_customer_gateway" "gcp_cgw_1" {
  bgp_asn    = var.gcp_bgp_asn
  ip_address = google_compute_ha_vpn_gateway.ha_gateway.vpn_interfaces[1].ip_address
  type       = "ipsec.1"

  tags = merge(var.tags, {
    Name = "${var.environment}-gcp-customer-gw-1"
  })
}

# Inside CIDRs are non-overlapping /30 subnets within 169.254.0.0/16 avoiding AWS-reserved ranges.
# In each /30, .1 is the AWS VGW and .2 is the GCP Cloud Router interface.
resource "aws_vpn_connection" "vpn_conn_0" {
  vpn_gateway_id      = aws_vpn_gateway.vpn_gw.id
  customer_gateway_id = aws_customer_gateway.gcp_cgw_0.id
  type                = "ipsec.1"
  static_routes_only  = false

  tunnel1_inside_cidr   = "169.254.10.0/30"
  tunnel1_preshared_key = local.psk["0-1"]
  tunnel1_ike_versions  = ["ikev2"]

  tunnel2_inside_cidr   = "169.254.10.4/30"
  tunnel2_preshared_key = local.psk["0-2"]
  tunnel2_ike_versions  = ["ikev2"]

  tags = merge(var.tags, {
    Name = "${var.environment}-aws-to-gcp-conn-0"
  })
}

resource "aws_vpn_connection" "vpn_conn_1" {
  vpn_gateway_id      = aws_vpn_gateway.vpn_gw.id
  customer_gateway_id = aws_customer_gateway.gcp_cgw_1.id
  type                = "ipsec.1"
  static_routes_only  = false

  tunnel1_inside_cidr   = "169.254.11.0/30"
  tunnel1_preshared_key = local.psk["1-1"]
  tunnel1_ike_versions  = ["ikev2"]

  tunnel2_inside_cidr   = "169.254.11.4/30"
  tunnel2_preshared_key = local.psk["1-2"]
  tunnel2_ike_versions  = ["ikev2"]

  tags = merge(var.tags, {
    Name = "${var.environment}-aws-to-gcp-conn-1"
  })

  # Prevent AWS ConcurrentMutationLimitExceeded rate limit when creating VPN connections on same VGW
  depends_on = [aws_vpn_connection.vpn_conn_0]
}

# -----------------------------------------------------------------------------
# GCP: VPC, Subnets, Cloud Router, Cloud NAT, HA VPN Gateway, Tunnels, BGP Peers
# -----------------------------------------------------------------------------
module "gcp_vpc" {
  source                          = "./modules/gcp/vpc"
  vpc_name                        = "${var.environment}-gcp-vpc"
  delete_default_routes_on_create = false
  auto_create_subnetworks         = false
  routing_mode                    = "GLOBAL"

  subnets = [
    for i, cidr in var.gcp_private_subnets : {
      name                     = "${var.environment}-api-subnet-${i + 1}"
      region                   = var.gcp_region
      purpose                  = "PRIVATE"
      role                     = "ACTIVE"
      private_ip_google_access = true
      ip_cidr_range            = cidr
    }
  ]

  firewall_data = [
    {
      name          = "${var.environment}-allow-from-aws-alb"
      description   = "Allow HTTP web traffic from the AWS VPC over VPN"
      direction     = "INGRESS"
      priority      = 1000
      source_ranges = [var.aws_vpc_cidr]
      allow_list = [
        {
          protocol = "tcp"
          ports    = ["80", "443"]
        },
        {
          protocol = "icmp"
        }
      ]
    },
    {
      name          = "${var.environment}-allow-iap-ssh"
      description   = "Allow secure IAP bastionless SSH administration"
      direction     = "INGRESS"
      priority      = 1000
      source_ranges = ["35.235.240.0/20"]
      allow_list = [
        {
          protocol = "tcp"
          ports    = ["22"]
        }
      ]
    }
  ]
}

resource "google_compute_router" "router" {
  name    = "${var.environment}-cr-ha-vpn"
  region  = var.gcp_region
  network = module.gcp_vpc.vpc_name

  bgp {
    asn               = var.gcp_bgp_asn
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]
  }
}

# Cloud NAT enables backend instances to fetch updates without allocating public IPs
resource "google_compute_router_nat" "nat" {
  name                               = "${var.environment}-gcp-cloud-nat"
  router                             = google_compute_router.router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_ha_vpn_gateway" "ha_gateway" {
  name    = "${var.environment}-gcp-ha-vpn-gw"
  region  = var.gcp_region
  network = module.gcp_vpc.vpc_name
}

resource "google_compute_external_vpn_gateway" "external_gw" {
  name            = "${var.environment}-aws-peer-gw"
  redundancy_type = "FOUR_IPS_REDUNDANCY"

  interface {
    id         = 0
    ip_address = aws_vpn_connection.vpn_conn_0.tunnel1_address
  }

  interface {
    id         = 1
    ip_address = aws_vpn_connection.vpn_conn_0.tunnel2_address
  }

  interface {
    id         = 2
    ip_address = aws_vpn_connection.vpn_conn_1.tunnel1_address
  }

  interface {
    id         = 3
    ip_address = aws_vpn_connection.vpn_conn_1.tunnel2_address
  }
}

resource "google_compute_vpn_tunnel" "tunnel" {
  for_each = local.vpn_tunnels

  name                            = "${var.environment}-ha-vpn-tunnel-${each.key}"
  region                          = var.gcp_region
  vpn_gateway                     = google_compute_ha_vpn_gateway.ha_gateway.id
  vpn_gateway_interface           = each.value.gcp_interface
  peer_external_gateway           = google_compute_external_vpn_gateway.external_gw.id
  peer_external_gateway_interface = each.value.peer_interface
  shared_secret                   = local.psk[each.key]
  router                          = google_compute_router.router.id
  ike_version                     = 2
}

resource "google_compute_router_interface" "interface" {
  for_each = local.vpn_tunnels

  name       = "${var.environment}-cr-if-${each.key}"
  router     = google_compute_router.router.name
  region     = var.gcp_region
  ip_range   = "${local.aws_vpn_connections[each.value.conn]["tunnel${each.value.aws_tunnel}_cgw_inside_address"]}/30"
  vpn_tunnel = google_compute_vpn_tunnel.tunnel[each.key].name
}

resource "google_compute_router_peer" "bgp_peer" {
  for_each = local.vpn_tunnels

  name                      = "${var.environment}-bgp-peer-${each.key}"
  router                    = google_compute_router.router.name
  region                    = var.gcp_region
  peer_ip_address           = local.aws_vpn_connections[each.value.conn]["tunnel${each.value.aws_tunnel}_vgw_inside_address"]
  peer_asn                  = aws_vpn_gateway.vpn_gw.amazon_side_asn
  interface                 = google_compute_router_interface.interface[each.key].name
  advertised_route_priority = 100
}

# -----------------------------------------------------------------------------
# GCP Private Backend: Multi-Zone Compute Engine instances (No Public IP)
# -----------------------------------------------------------------------------
locals {
  # Deterministic static private IPs (.10) in each GCP private subnet
  gcp_private_ips = [for cidr in var.gcp_private_subnets : cidrhost(cidr, 10)]

  # Combined target IP list for ALB registration (GCP nodes + optional custom external endpoints)
  all_target_ips = concat(local.gcp_private_ips, var.custom_external_endpoints)
}

resource "google_compute_instance" "backend_api" {
  count        = length(var.gcp_private_subnets)
  name         = "${var.environment}-gcp-api-${count.index + 1}"
  machine_type = var.gcp_machine_type
  zone         = var.gcp_zones[count.index]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
    }
  }

  network_interface {
    subnetwork = "${var.environment}-api-subnet-${count.index + 1}"
    network_ip = local.gcp_private_ips[count.index]
    # NOTE: NO access_config block -> strictly private, zero public IP!
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -xe
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y nginx curl

    VM_NAME=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/name" || hostname)
    VM_ZONE=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/zone" | awk -F/ '{print $NF}' || echo "unknown")
    INTERNAL_IP=$(curl -sf -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip" || hostname -I | awk '{print $1}')

    cat > /var/www/html/index.html <<HTML
    <!DOCTYPE html>
    <html>
    <head><title>GCP Private External API</title></head>
    <body style="font-family: Arial, sans-serif; text-align: center; margin-top: 50px;">
      <h2>Hello from GCP Private External API Service</h2>
      <p><b>Instance Name:</b> $VM_NAME</p>
      <p><b>GCP Zone:</b> $VM_ZONE</p>
      <p><b>Private IP:</b> $INTERNAL_IP</p>
      <p><b>Cloud Provider:</b> Google Cloud Platform (GCP)</p>
      <p><b>Fronted By:</b> AWS Application Load Balancer (ALB) via Site-to-Site VPN</p>
      <p><b>Status:</b> Healthy</p>
    </body>
    </html>
    HTML

    systemctl enable --now nginx
  EOF

  tags = ["private-api", "vpn-target"]

  depends_on = [
    module.gcp_vpc,
    google_compute_router_nat.nat
  ]
}

# -----------------------------------------------------------------------------
# AWS: Security Group for Application Load Balancer
# -----------------------------------------------------------------------------
module "alb_sg" {
  source = "./modules/aws/security-groups"
  name   = "${var.environment}-alb-sg"
  vpc_id = module.aws_vpc.vpc_id

  ingress_rules = [
    {
      description     = "Inbound HTTP from Internet"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      security_groups = []
      cidr_blocks     = ["0.0.0.0/0"]
    },
    {
      description     = "Inbound HTTPS from Internet"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      security_groups = []
      cidr_blocks     = ["0.0.0.0/0"]
    }
  ]

  egress_rules = [
    {
      description = "Egress to GCP Private API Subnets over VPN"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = [var.gcp_vpc_cidr]
    },
    {
      description = "Egress to AWS VPC subnets"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [var.aws_vpc_cidr]
    }
  ]

  tags = merge(var.tags, {
    Name = "${var.environment}-alb-sg"
  })
}

# -----------------------------------------------------------------------------
# AWS: Target Group (target_type = "ip") for Hybrid / External Private Workloads
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "ext_api_tg" {
  name                 = "${var.environment}-ext-api-tg"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = module.aws_vpc.vpc_id
  deregistration_delay = 30

  health_check {
    enabled             = true
    interval            = 15
    path                = "/"
    port                = "80"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-ext-api-tg"
  })
}

# Attach external private IP endpoints to Target Group.
# IMPORTANT: For targets outside the VPC (e.g. over VPN / Direct Connect),
# AWS requires availability_zone = "all".
resource "aws_lb_target_group_attachment" "ext_api_attachment" {
  count             = length(local.all_target_ips)
  target_group_arn  = aws_lb_target_group.ext_api_tg.arn
  target_id         = local.all_target_ips[count.index]
  port              = 80
  availability_zone = "all"

  depends_on = [
    google_compute_router_peer.bgp_peer,
    google_compute_instance.backend_api
  ]
}

# -----------------------------------------------------------------------------
# AWS: SSL/TLS Certificate for Application Load Balancer
# -----------------------------------------------------------------------------
# Generates a 2048-bit RSA private key and self-signed certificate if no existing
# ACM certificate ARN is supplied in var.acm_certificate_arn.
resource "tls_private_key" "alb_cert_key" {
  count     = var.acm_certificate_arn == null || var.acm_certificate_arn == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "alb_cert" {
  count           = var.acm_certificate_arn == null || var.acm_certificate_arn == "" ? 1 : 0
  private_key_pem = tls_private_key.alb_cert_key[0].private_key_pem

  subject {
    common_name  = var.domain_name
    organization = "Enterprise Multi-Cloud Ingress"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "alb_cert" {
  count            = var.acm_certificate_arn == null || var.acm_certificate_arn == "" ? 1 : 0
  private_key      = tls_private_key.alb_cert_key[0].private_key_pem
  certificate_body = tls_self_signed_cert.alb_cert[0].cert_pem

  tags = merge(var.tags, {
    Name = "${var.environment}-alb-ssl-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  certificate_arn = var.acm_certificate_arn != null && var.acm_certificate_arn != "" ? var.acm_certificate_arn : aws_acm_certificate.alb_cert[0].arn
}

# -----------------------------------------------------------------------------
# AWS: Internet-Facing Application Load Balancer (HTTP & HTTPS Listeners)
# -----------------------------------------------------------------------------
module "alb" {
  source                     = "./modules/aws/load-balancer"
  lb_name                    = "${var.environment}-public-alb"
  lb_is_internal             = false
  load_balancer_type         = "application"
  security_groups            = [module.alb_sg.id]
  subnets                    = module.aws_vpc.public_subnets
  enable_deletion_protection = var.environment == "prod" ? false : false

  target_groups = []

  listeners = [
    # HTTP Port 80 Listener (Redirects HTTP to HTTPS :443)
    {
      listener_port     = 80
      listener_protocol = "HTTP"
      default_actions = [
        var.enable_http_redirect ? {
          type             = "redirect"
          target_group_arn = null
          redirect = {
            port        = "443"
            protocol    = "HTTPS"
            status_code = "HTTP_301"
          }
          } : {
          type             = "forward"
          target_group_arn = aws_lb_target_group.ext_api_tg.arn
          redirect         = null
        }
      ]
    },
    # HTTPS Port 443 Listener (Terminates SSL and forwards to GCP private backend)
    {
      listener_port     = 443
      listener_protocol = "HTTPS"
      ssl_policy        = var.ssl_policy
      certificate_arn   = local.certificate_arn
      default_actions = [
        {
          type             = "forward"
          target_group_arn = aws_lb_target_group.ext_api_tg.arn
          redirect         = null
        }
      ]
    }
  ]

  tags = var.tags
}