# ==============================================================================
# Global & Shared Configuration
# ==============================================================================

variable "environment" {
  type        = string
  default     = "prod"
  description = "Deployment environment name (e.g. dev, staging, prod)."
}

variable "tags" {
  type        = map(string)
  description = "Resource tags applied to AWS resources."
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "aws-lb-private-external-api"
  }
}

# ==============================================================================
# AWS Configuration
# ==============================================================================

variable "aws_region" {
  type        = string
  description = "AWS deployment region."
  default     = "us-east-1"
}

variable "azs" {
  type        = list(string)
  description = "AWS Availability Zones to deploy subnets into."
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "aws_vpc_cidr" {
  type        = string
  description = "CIDR block for the AWS VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  type        = list(string)
  description = "CIDR blocks for AWS public subnets (housing the Application Load Balancer)."
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  type        = list(string)
  description = "CIDR blocks for AWS private subnets."
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "aws_bgp_asn" {
  type        = number
  description = "BGP Autonomous System Number (ASN) for AWS Virtual Private Gateway."
  default     = 64512
}

# ==============================================================================
# HTTPS & SSL/TLS Configuration
# ==============================================================================

variable "acm_certificate_arn" {
  type        = string
  default     = null
  description = "Optional existing ACM Certificate ARN. If null or empty, a self-signed TLS certificate is generated and imported into ACM."
}

variable "domain_name" {
  type        = string
  default     = "api.example.internal"
  description = "Domain name / Common Name (CN) for the self-signed SSL/TLS certificate."
}

variable "ssl_policy" {
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  description = "Security policy for the HTTPS ALB listener (e.g. ELBSecurityPolicy-TLS13-1-2-2021-06)."
}

variable "enable_http_redirect" {
  type        = bool
  default     = true
  description = "Whether to redirect HTTP (port 80) traffic to HTTPS (port 443)."
}

# ==============================================================================
# Google Cloud Platform (GCP) Configuration (Private External API)
# ==============================================================================

variable "gcp_project_id" {
  type        = string
  description = "Google Cloud Project ID hosting the private external API compute workloads."
}

variable "gcp_region" {
  type        = string
  description = "GCP deployment region for Cloud HA VPN, Cloud Router, and backend subnets."
  default     = "us-central1"
}

variable "gcp_zones" {
  type        = list(string)
  description = "GCP Availability Zones corresponding to the private backend subnets."
  default     = ["us-central1-a", "us-central1-b", "us-central1-c"]
}

variable "gcp_vpc_cidr" {
  type        = string
  description = "CIDR block for the GCP VPC."
  default     = "10.20.0.0/16"
}

variable "gcp_private_subnets" {
  type        = list(string)
  description = "CIDR blocks for GCP private subnets housing the private API compute instances."
  default     = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
}

variable "gcp_bgp_asn" {
  type        = number
  description = "BGP Autonomous System Number (ASN) for GCP Cloud Router."
  default     = 64514
}

variable "gcp_machine_type" {
  type        = string
  description = "Machine type for the private backend Compute Engine instances in GCP."
  default     = "e2-small"
}

# ==============================================================================
# External Target Configuration
# ==============================================================================

variable "custom_external_endpoints" {
  type        = list(string)
  description = "Optional additional external private IP addresses to register into the ALB Target Group."
  default     = []
}
