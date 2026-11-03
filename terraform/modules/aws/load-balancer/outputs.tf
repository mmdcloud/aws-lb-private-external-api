# =============================================================================
# Load Balancer Outputs
# =============================================================================

output "lb_id" {
  description = "The ARN of the load balancer (matches arn)."
  value       = aws_lb.lb.id
}

output "lb_arn" {
  description = "The ARN of the load balancer."
  value       = aws_lb.lb.arn
}

output "lb_dns_name" {
  description = "The DNS name of the load balancer."
  value       = aws_lb.lb.dns_name
}

output "lb_zone_id" {
  description = "The canonical hosted zone ID of the load balancer."
  value       = aws_lb.lb.zone_id
}

output "target_groups" {
  description = "List of target group objects created."
  value       = aws_lb_target_group.lb_target_group[*]
}

output "target_group_arns" {
  description = "List of ARNs of the target groups created."
  value       = aws_lb_target_group.lb_target_group[*].arn
}

output "target_group_names" {
  description = "List of names of the target groups created."
  value       = aws_lb_target_group.lb_target_group[*].name
}

output "target_groups_map" {
  description = "Map of target group name to its ARN."
  value       = { for tg in aws_lb_target_group.lb_target_group : tg.name => tg.arn }
}

output "listeners" {
  description = "List of listener objects created."
  value       = aws_lb_listener.lb_listener[*]
}
