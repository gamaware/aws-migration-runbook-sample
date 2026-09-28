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

output "internet_exposure" {
  description = "Counts of resources that make the VPC reachable from, or route to, the internet; all zero when internet_egress is false."
  value = {
    internet_gateways   = length(aws_internet_gateway.this)
    public_nat_gateways = length([for n in aws_nat_gateway.this : n if n.connectivity_type != "private"])
    elastic_ips         = length(aws_eip.nat)
    default_routes      = length(aws_route.public_internet) + length(aws_route.app_internet)
    public_ip_subnets   = length([for s in concat(aws_subnet.public, aws_subnet.app, aws_subnet.data) : s if s.map_public_ip_on_launch])
  }
}
