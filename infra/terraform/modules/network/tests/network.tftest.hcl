# Offline tests: the mock provider answers every AWS call, so no credentials or network access are needed.
mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  name        = "hg-test"
  vpc_cidr    = "10.60.0.0/16"
  azs         = ["us-east-1a", "us-east-1b"]
  onprem_cidr = "10.40.0.0/16"
  vpn_peer_ip = "203.0.113.20"
  vpn_bgp_asn = 65010
  kms_key_arn = "arn:aws:kms:us-east-1:111122223333:key/11111111-2222-3333-4444-555555555555"
}

run "one_subnet_per_tier_per_az" {
  command = apply

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.app) == 2 && length(aws_subnet.data) == 2
    error_message = "Each tier needs one subnet per Availability Zone."
  }

  assert {
    condition     = length(distinct([for s in concat(aws_subnet.public, aws_subnet.app, aws_subnet.data) : s.cidr_block])) == 6
    error_message = "Subnet CIDRs must not repeat."
  }

  assert {
    condition     = alltrue([for s in concat(aws_subnet.public, aws_subnet.app, aws_subnet.data) : !s.map_public_ip_on_launch])
    error_message = "No subnet may assign public IPs on launch; only the NAT gateways face the internet."
  }
}

run "data_tier_has_no_internet_route" {
  command = apply

  assert {
    condition     = length(aws_route.app_internet) == 2 && alltrue([for r in concat(aws_route.app_internet, aws_route.public_internet) : r.route_table_id != aws_route_table.data.id])
    error_message = "Only application route tables get a NAT route; the data route table relies on VPN propagation."
  }

  assert {
    condition     = aws_vpn_gateway_route_propagation.data.vpn_gateway_id == aws_vpn_gateway.this.id
    error_message = "The data route table must learn the on-premises routes from the VPN gateway."
  }
}

run "private_only_mode_has_no_internet_path" {
  command = apply

  variables {
    internet_egress     = false
    interface_endpoints = []
  }

  assert {
    condition     = length(aws_internet_gateway.this) == 0 && length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0
    error_message = "Without internet egress the module must not create an internet gateway, NAT gateways or Elastic IPs."
  }

  assert {
    condition     = length(aws_subnet.public) == 0 && length(aws_route.public_internet) == 0 && length(aws_route.app_internet) == 0
    error_message = "Without internet egress there are no public subnets and no default routes."
  }

  assert {
    condition     = length(aws_subnet.app) == 2 && length(aws_subnet.data) == 2 && length(aws_vpn_gateway_route_propagation.app) == 2
    error_message = "The application and data tiers still exist and learn the data center routes from the VPN."
  }

  assert {
    condition     = alltrue([for v in values(output.internet_exposure) : v == 0])
    error_message = "internet_exposure must report zero for every internet-facing resource type."
  }

  assert {
    condition     = length(aws_vpc_endpoint.interface) == 0
    error_message = "The private-only mode must be able to skip the interface endpoints."
  }
}

run "aws_apis_through_vpc_endpoints" {
  command = apply

  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" && length(aws_vpc_endpoint.s3.route_table_ids) == 3
    error_message = "The S3 gateway endpoint must serve both application route tables and the data route table."
  }

  assert {
    condition     = toset(keys(aws_vpc_endpoint.interface)) == toset(["ecr.api", "ecr.dkr", "logs", "secretsmanager"]) && alltrue([for e in aws_vpc_endpoint.interface : e.private_dns_enabled])
    error_message = "ECR, CloudWatch Logs and Secrets Manager need interface endpoints with private DNS."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.endpoints_https.cidr_ipv4 == "10.60.0.0/16" && aws_vpc_security_group_ingress_rule.endpoints_https.from_port == 443
    error_message = "The interface endpoints accept HTTPS from the VPC only."
  }

  assert {
    condition     = length(aws_vpc_peering_connection.storefront) == 0 && output.storefront_peering_connection_id == null
    error_message = "Without a storefront VPC the module creates no peering."
  }
}

run "storefront_peering_routes_only_its_cidr" {
  command = apply

  variables {
    storefront_vpc = { id = "vpc-0a1b2c3d4e5f67890", cidr = "10.50.0.0/16" }
  }

  assert {
    condition     = aws_vpc_peering_connection.storefront[0].peer_vpc_id == "vpc-0a1b2c3d4e5f67890"
    error_message = "The peering must connect to the storefront VPC."
  }

  assert {
    condition     = length(aws_route.app_to_storefront) == 2 && alltrue([for r in aws_route.app_to_storefront : r.destination_cidr_block == "10.50.0.0/16"])
    error_message = "Each application route table routes exactly the storefront CIDR through the peering."
  }
}

run "vpn_routes_only_the_data_center" {
  command = apply

  assert {
    condition     = aws_vpn_connection.onprem.static_routes_only && aws_vpn_connection_route.onprem.destination_cidr_block == "10.40.0.0/16"
    error_message = "The VPN must route exactly the on-premises CIDR with static routes."
  }

  assert {
    condition     = aws_vpn_connection.onprem.tunnel1_ike_versions == toset(["ikev2"]) && aws_vpn_connection.onprem.tunnel2_ike_versions == toset(["ikev2"])
    error_message = "Both tunnels must use IKEv2."
  }
}

run "flow_logs_capture_all_traffic" {
  command = apply

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL" && aws_cloudwatch_log_group.flow_logs.retention_in_days >= 365
    error_message = "Flow logs must capture accepted and rejected traffic and keep it for a year."
  }
}

run "rejects_overlapping_cidrs" {
  command = plan

  variables {
    onprem_cidr = "10.60.128.0/17"
  }

  expect_failures = [var.onprem_cidr]
}

run "rejects_single_az" {
  command = plan

  variables {
    azs = ["us-east-1a"]
  }

  expect_failures = [var.azs]
}
