mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  zone_id      = "Z0123456789EXAMPLE"
  alb_dns_name = "mock-1234567890.us-east-1.elb.amazonaws.com"
  alb_zone_id  = "Z35SXDOTRQ7X7K"
  records = {
    "shop.example.com" = { onprem_ip = "203.0.113.10" }
    "api.example.com"  = { onprem_ip = "203.0.113.11" }
  }
}

run "before_cutover_all_traffic_stays_on_premises" {
  command = apply

  assert {
    condition     = alltrue([for r in aws_route53_record.onprem : one(r.weighted_routing_policy).weight == 100]) && alltrue([for r in aws_route53_record.aws : one(r.weighted_routing_policy).weight == 0])
    error_message = "Until the DNS switch, the aws member of each pair must carry weight 0."
  }

  assert {
    condition     = output.active_target == "onprem"
    error_message = "The default must keep customers on the data center."
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
