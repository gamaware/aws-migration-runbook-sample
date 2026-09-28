mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  name                  = "hg-test"
  zone_name             = "example.com"
  vpc_id                = "vpc-0123456789abcdef0"
  associated_vpc_ids    = ["vpc-0a1b2c3d4e5f67890"]
  resolver_subnet_ids   = ["subnet-0bbbbbbbbbbbbbbb1", "subnet-0bbbbbbbbbbbbbbb2"]
  resolver_client_cidrs = ["10.40.0.0/16"]
  alb_dns_name          = "internal-mock-1234567890.us-east-1.elb.amazonaws.com"
  alb_zone_id           = "Z35SXDOTRQ7X7K"
  records = {
    "warehouse.example.com" = { onprem_ip = "203.0.113.10" }
    "api.example.com"       = { onprem_ip = "203.0.113.11" }
  }
}

run "records_live_in_a_private_zone" {
  command = apply

  assert {
    condition     = toset([for v in aws_route53_zone.private.vpc : v.vpc_id]) == toset(["vpc-0123456789abcdef0", "vpc-0a1b2c3d4e5f67890"])
    error_message = "The zone must be private, associated with the wave 1 VPC and the storefront VPC."
  }

  assert {
    condition     = alltrue([for r in concat(values(aws_route53_record.onprem), values(aws_route53_record.aws)) : r.zone_id == aws_route53_zone.private.zone_id])
    error_message = "Every weighted member must live in the private zone, never in the public one."
  }

  assert {
    condition     = aws_route53_resolver_endpoint.inbound.direction == "INBOUND" && length(aws_route53_resolver_endpoint.inbound.ip_address) == 2
    error_message = "The corporate resolvers need an inbound endpoint with an address in each Availability Zone."
  }

  assert {
    condition     = toset([for r in aws_vpc_security_group_ingress_rule.resolver : r.cidr_ipv4]) == toset(["10.40.0.0/16"]) && toset([for r in aws_vpc_security_group_ingress_rule.resolver : r.ip_protocol]) == toset(["tcp", "udp"]) && alltrue([for r in aws_vpc_security_group_ingress_rule.resolver : r.from_port == 53 && r.to_port == 53])
    error_message = "The inbound endpoint answers DNS on port 53 to the corporate network only."
  }
}

run "rejects_resolver_open_to_the_internet" {
  command = plan

  variables {
    resolver_client_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.resolver_client_cidrs]
}

run "before_cutover_all_traffic_stays_on_premises" {
  command = apply

  assert {
    condition     = alltrue([for r in aws_route53_record.onprem : one(r.weighted_routing_policy).weight == 100]) && alltrue([for r in aws_route53_record.aws : one(r.weighted_routing_policy).weight == 0])
    error_message = "Until the DNS switch, the aws member of each pair must carry weight 0."
  }

  assert {
    condition     = output.active_target == "onprem"
    error_message = "The default must keep users on the data center."
  }

  assert {
    condition     = alltrue([for r in aws_route53_record.onprem : r.ttl == 60])
    error_message = "On-premises records keep a 60-second TTL so a rollback propagates fast."
  }
}

run "cutover_moves_every_name_at_once" {
  command = apply

  variables {
    traffic_weights = { onprem = 0, aws = 100 }
  }

  assert {
    condition     = alltrue([for r in aws_route53_record.aws : one(r.weighted_routing_policy).weight == 100]) && alltrue([for r in aws_route53_record.onprem : one(r.weighted_routing_policy).weight == 0])
    error_message = "After the switch, every name must resolve to the load balancer."
  }

  assert {
    condition     = alltrue([for r in aws_route53_record.aws : !one(r.alias).evaluate_target_health])
    error_message = "Alias records must not evaluate target health; an unhealthy target would fail over to the data center, a second writer."
  }
}

run "rollback_restores_the_data_center" {
  command = apply

  variables {
    traffic_weights = { onprem = 100, aws = 0 }
  }

  assert {
    condition     = output.active_target == "onprem"
    error_message = "Rollback weights must send traffic back to the data center."
  }
}

run "rejects_a_traffic_split" {
  command = plan

  variables {
    traffic_weights = { onprem = 50, aws = 50 }
  }

  expect_failures = [var.traffic_weights]
}

run "rejects_no_target" {
  command = plan

  variables {
    traffic_weights = { onprem = 0, aws = 0 }
  }

  expect_failures = [var.traffic_weights]
}

run "rejects_the_old_ttl" {
  command = plan

  variables {
    onprem_ttl = 3600
  }

  expect_failures = [var.onprem_ttl]
}
