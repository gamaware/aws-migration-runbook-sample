output "database_address" {
  description = "RDS endpoint of the live test instance."
  value       = module.database.address
}

output "vpn_connection_id" {
  description = "VPN connection created by the live test."
  value       = module.network.vpn_connection_id
}
