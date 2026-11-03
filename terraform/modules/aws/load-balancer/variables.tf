# =============================================================================
# Load Balancer Variables
# =============================================================================

variable "lb_name" {
  type        = string
  description = "The name of the load balancer."
}

variable "lb_is_internal" {
  type        = bool
  default     = false
  description = "Boolean determining if the load balancer is internal or internet-facing."
}

variable "lb_ip_address_type" {
  type        = string
  default     = "ipv4"
  description = "The type of IP addresses used by the subnets for your load balancer."
}

variable "load_balancer_type" {
  type        = string
  default     = "application"
  description = "The type of load balancer to create (application or network)."
}

variable "security_groups" {
  type        = list(string)
  default     = []
  description = "A list of security group IDs to assign to the LB (application type only)."
}

variable "subnets" {
  type        = list(string)
  description = "A list of subnet IDs to attach to the LB."
}

variable "enable_deletion_protection" {
  type        = bool
  default     = false
  description = "If true, deletion of the load balancer will be disabled via the AWS API."
}

variable "target_groups" {
  type        = any
  default     = []
  description = "List of target group configurations."
}

variable "target_attachments" {
  type        = any
  default     = []
  description = "List of target group attachments (supports IP targets with availability_zone = 'all')."
}

variable "listeners" {
  type        = any
  default     = []
  description = "List of listener configurations."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "A map of tags to add to all resources."
}
