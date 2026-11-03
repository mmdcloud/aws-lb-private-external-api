# =============================================================================
# AWS Application / Network Load Balancer Module
# =============================================================================

# Load Balancer Creation
resource "aws_lb" "lb" {
  name                       = var.lb_name
  internal                   = var.lb_is_internal
  ip_address_type            = var.lb_ip_address_type
  load_balancer_type         = var.load_balancer_type
  security_groups            = var.load_balancer_type == "application" ? var.security_groups : null
  subnets                    = var.subnets
  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(
    {
      Name = var.lb_name
    },
    var.tags
  )
}

# Target Groups
resource "aws_lb_target_group" "lb_target_group" {
  count           = length(var.target_groups)
  name            = var.target_groups[count.index].target_group_name
  port            = var.target_groups[count.index].target_port
  ip_address_type = lookup(var.target_groups[count.index], "target_ip_address_type", "ipv4")
  protocol        = var.target_groups[count.index].target_protocol
  target_type     = var.target_groups[count.index].target_type
  vpc_id          = var.target_groups[count.index].target_vpc_id

  health_check {
    interval            = lookup(var.target_groups[count.index], "health_check_interval", 30)
    path                = lookup(var.target_groups[count.index], "health_check_path", "/")
    enabled             = lookup(var.target_groups[count.index], "health_check_enabled", true)
    protocol            = lookup(var.target_groups[count.index], "health_check_protocol", "HTTP")
    timeout             = lookup(var.target_groups[count.index], "health_check_timeout", 5)
    healthy_threshold   = lookup(var.target_groups[count.index], "health_check_healthy_threshold", 3)
    unhealthy_threshold = lookup(var.target_groups[count.index], "health_check_unhealthy_threshold", 3)
    port                = lookup(var.target_groups[count.index], "health_check_port", "traffic-port")
    matcher             = lookup(var.target_groups[count.index], "health_check_matcher", "200")
  }

  tags = merge(
    {
      Name = var.target_groups[count.index].target_group_name
    },
    var.tags
  )
}

# Target Group Attachments (Supports external IP targets with availability_zone = "all")
resource "aws_lb_target_group_attachment" "attachments" {
  count             = length(var.target_attachments)
  target_group_arn  = var.target_attachments[count.index].target_group_arn != null ? var.target_attachments[count.index].target_group_arn : aws_lb_target_group.lb_target_group[lookup(var.target_attachments[count.index], "target_group_index", 0)].arn
  target_id         = var.target_attachments[count.index].target_id
  port              = lookup(var.target_attachments[count.index], "port", null)
  availability_zone = lookup(var.target_attachments[count.index], "availability_zone", null)
}

# Listeners
resource "aws_lb_listener" "lb_listener" {
  count             = length(var.listeners)
  load_balancer_arn = aws_lb.lb.arn
  port              = var.listeners[count.index].listener_port
  protocol          = var.listeners[count.index].listener_protocol
  ssl_policy        = lookup(var.listeners[count.index], "ssl_policy", null)
  certificate_arn   = lookup(var.listeners[count.index], "certificate_arn", null)

  dynamic "default_action" {
    for_each = var.listeners[count.index].default_actions
    content {
      type             = default_action.value["type"]
      target_group_arn = lookup(default_action.value, "target_group_arn", null) != null ? default_action.value["target_group_arn"] : aws_lb_target_group.lb_target_group[lookup(default_action.value, "target_group_index", 0)].arn
    }
  }

  tags = merge(
    {
      Name = "${var.lb_name}-listener-${var.listeners[count.index].listener_port}"
    },
    var.tags
  )
}
