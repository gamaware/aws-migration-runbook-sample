output "vpc_id" {
  description = "ID of the target VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the target VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnets, one per Availability Zone (NAT gateways only; the load balancer is internal)."
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "Application subnets, one per Availability Zone (internal load balancer, ECS tasks, interface endpoints and the DMS replication instance)."
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

output "s3_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint, for security group egress to S3."
  value       = aws_vpc_endpoint.s3.prefix_list_id
}

output "interface_endpoint_services" {
  description = "Services reached through interface VPC endpoints instead of the internet."
  value       = sort(keys(aws_vpc_endpoint.interface))
}

output "storefront_peering_connection_id" {
  description = "VPC peering connection to the storefront VPC, or null when there is none."
  value       = one(aws_vpc_peering_connection.storefront[*].id)
}
