# =============================================================================
# Infrastructure Outputs & Day-2 Operational Commands
# =============================================================================

output "alb_dns_name" {
  description = "Public DNS name of the AWS Application Load Balancer."
  value       = module.alb.lb_dns_name
}

output "alb_arn" {
  description = "ARN of the AWS Application Load Balancer."
  value       = module.alb.lb_arn
}

output "target_group_arn" {
  description = "ARN of the AWS IP Target Group fronting the private external API."
  value       = aws_lb_target_group.ext_api_tg.arn
}

output "target_group_name" {
  description = "Name of the AWS IP Target Group."
  value       = aws_lb_target_group.ext_api_tg.name
}

output "registered_external_endpoints" {
  description = "List of external private IP endpoints registered into the AWS ALB Target Group (availability_zone = 'all')."
  value       = local.all_target_ips
}

output "gcp_instance_names" {
  description = "Names of the GCP Compute Engine instances hosting the private external API."
  value       = google_compute_instance.backend_api[*].name
}

output "gcp_instance_private_ips" {
  description = "Private IP addresses of the GCP Compute Engine instances."
  value       = google_compute_instance.backend_api[*].network_interface[0].network_ip
}

output "aws_vpn_connection_ids" {
  description = "IDs of the AWS Site-to-Site VPN connections."
  value = [
    aws_vpn_connection.vpn_conn_0.id,
    aws_vpn_connection.vpn_conn_1.id
  ]
}

output "bgp_status_aws_command" {
  description = "AWS CLI command to check Site-to-Site VPN tunnels and BGP state."
  value       = "aws ec2 describe-vpn-connections --vpn-connection-ids ${aws_vpn_connection.vpn_conn_0.id} ${aws_vpn_connection.vpn_conn_1.id} --region ${var.aws_region} --query 'VpnConnections[*].VgwTelemetry'"
}

output "bgp_status_gcp_command" {
  description = "gcloud CLI command to verify all four GCP Cloud Router BGP sessions are ESTABLISHED."
  value       = "gcloud compute routers get-status ${google_compute_router.router.name} --region ${var.gcp_region} --project ${var.gcp_project_id}"
}

output "test_alb_curl_command" {
  description = "Command to test live traffic distribution and verify multi-cloud connectivity."
  value       = "curl -s http://${module.alb.lb_dns_name}"
}

