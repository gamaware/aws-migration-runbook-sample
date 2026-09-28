output "database_address" {
  description = "RDS endpoint of the live test instance."
  value       = module.database.address
}

output "vpn_connection_id" {
  description = "VPN connection created by the live test."
  value       = module.network.vpn_connection_id
}

output "internet_exposure" {
  description = "Internet-facing resource counts of the live network; the offline private-only test requires all zero."
  value       = module.network.internet_exposure
}

output "database_publicly_accessible" {
  description = "Whether the live database has a public address; must be false."
  value       = module.database.publicly_accessible
}

output "database_ingress_cidrs" {
  description = "CIDRs admitted to the live database; none may be 0.0.0.0/0."
  value       = module.database.onprem_client_cidrs
}
