output "active_target" {
  description = "Side that receives user traffic: onprem before the DNS switch, aws after it."
  value       = module.dns.active_target
}

output "nat_public_ips" {
  description = "Egress addresses to send to the parcel carrier for its allowlist (prerequisite P-04)."
  value       = module.network.nat_public_ips
}

output "alb_dns_name" {
  description = "Load balancer name, used by the smoke tests that run before the DNS switch."
  value       = module.app.alb_dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the load balancer, used by the break-glass DNS change batch."
  value       = module.app.alb_zone_id
}

output "database_address" {
  description = "RDS endpoint host name."
  value       = module.database.address
}

output "database_onprem_clients" {
  description = "On-premises hosts admitted to the database over the VPN."
  value       = module.database.onprem_client_cidrs
}

output "dms_task_ids" {
  description = "Replication task identifiers the runbook starts and monitors."
  value       = { forward = module.dms.forward_task_id, reverse = module.dms.reverse_task_id }
}

output "dms_credential_secrets" {
  description = "Secrets the DBA fills before the full load (prerequisite P-06)."
  value       = module.dms.credential_secrets
}

output "app_db_secret_arn" {
  description = "Secret the DBA fills with the orders API database user (manual step M-04)."
  value       = aws_secretsmanager_secret.app_db.arn
}
