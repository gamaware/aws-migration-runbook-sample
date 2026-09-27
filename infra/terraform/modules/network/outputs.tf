output "vpc_id" {
  description = "ID of the target VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the target VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnets, one per Availability Zone (ALB and NAT gateways)."
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "Application subnets, one per Availability Zone (ECS tasks and the DMS replication instance)."
  value       = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  description = "Data subnets without an internet route, one per Availability Zone (RDS)."
  value       = aws_subnet.data[*].id
}

output "nat_public_ips" {
  description = "Egress addresses the parcel carrier must allowlist before cutover."
  value       = aws_eip.nat[*].public_ip
}

output "vpn_connection_id" {
  description = "ID of the Site-to-Site VPN connection to the data center."
  value       = aws_vpn_connection.onprem.id
}
