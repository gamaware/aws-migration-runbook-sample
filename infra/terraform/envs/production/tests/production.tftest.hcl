# Composition tests: they prove that the numbers and identifiers in plan/ reach the resources, which is what the
# runbook and the report rely on. No AWS account is involved.
mock_provider "aws" {
  source = "../../tests/mocks"
}

override_data {
  target = data.aws_route53_zone.public
  values = { zone_id = "Z0123456789EXAMPLE", name = "example.com" }
}

override_resource {
  target = aws_acm_certificate.this
  values = {
    arn = "arn:aws:acm:us-east-1:111122223333:certificate/11111111-2222-3333-4444-555555555555"
    domain_validation_options = [
      { domain_name = "warehouse.example.com", resource_record_name = "_a1.warehouse.example.com.", resource_record_type = "CNAME", resource_record_value = "_b1.acm-validations.aws." },
      { domain_name = "api.example.com", resource_record_name = "_a2.api.example.com.", resource_record_type = "CNAME", resource_record_value = "_b2.acm-validations.aws." },
    ]
  }
}

variables {
  images = {
    web = "123456789012.dkr.ecr.us-east-1.amazonaws.com/harbor-web@sha256:1111111111111111111111111111111111111111111111111111111111111111"
    api = "123456789012.dkr.ecr.us-east-1.amazonaws.com/harbor-api@sha256:2222222222222222222222222222222222222222222222222222222222222222"
  }
}

run "plan_files_drive_the_environment" {
  command = apply

  assert {
    condition     = join(",", output.database_onprem_clients) == "10.40.3.51/32,10.40.5.61/32"
    error_message = "Only SRV-09 and SRV-10, the consumers in the plan's hybrid links, may reach RDS from the data center."
  }

  assert {
    condition     = output.dms_task_ids.forward == "harbor-wave1-full-load-cdc" && output.dms_task_ids.reverse == "harbor-wave1-reverse-cdc"
    error_message = "Task identifiers must match plan/data-migration.yaml; the runbook starts the tasks by these names."
  }

  assert {
    condition     = output.dms_credential_secrets.onprem.host == "10.40.4.41"
    error_message = "The DMS source must be SRV-07 from the inventory."
  }

  assert {
    condition     = length(module.network.app_subnet_ids) == 2
    error_message = "Wave 1 spans two Availability Zones."
  }
}

run "nothing_faces_the_internet" {
  command = apply

  assert {
    condition     = module.app.network_exposure.alb_internal && join(",", module.app.network_exposure.alb_subnet_ids) == join(",", sort(module.network.app_subnet_ids))
    error_message = "The load balancer must be internal and sit in the private application subnets."
  }

  assert {
    condition     = join(",", module.app.network_exposure.ingress_cidrs) == "10.40.0.0/16,10.50.0.0/16,10.60.0.0/16"
    error_message = "Only the corporate network, the storefront VPC and the VPC itself may reach the load balancer."
  }

  assert {
    condition     = length(setintersection(concat(module.app.network_exposure.egress_cidrs, module.app.network_exposure.ingress_cidrs), ["0.0.0.0/0", "::/0"])) == 0
    error_message = "No task or load balancer rule may open ingress or egress to 0.0.0.0/0 or ::/0."
  }

  assert {
    condition     = join(",", module.app.network_exposure.egress_cidrs) == "10.60.0.0/16,203.0.113.200/32,203.0.113.201/32"
    error_message = "Task HTTPS egress is the VPC (endpoints, load balancer) plus the carrier's published addresses from plan/target.yaml."
  }

  assert {
    condition     = module.app.network_exposure.access_log_bucket == "harbor-log-archive-777788889999-us-east-1"
    error_message = "Access logs must go to the central log archive bucket named in plan/target.yaml."
  }

  assert {
    condition     = output.storefront_peering_connection_id != null
    error_message = "The storefront VPC must be peered, or it cannot reach the internal load balancer."
  }

  assert {
    condition     = join(",", sort(keys(output.private_zone_ids))) == "api.example.com,warehouse.example.com"
    error_message = "Each wave 1 name gets its own private zone; a private example.com zone would shadow the storefront's other public names."
  }
}

run "users_stay_on_premises_until_the_switch" {
  command = apply

  assert {
    condition     = output.active_target == "onprem"
    error_message = "A plain apply must never move user traffic."
  }
}

run "dns_switch" {
  command = apply

  variables {
    traffic_weights = { onprem = 0, aws = 100 }
  }

  assert {
    condition     = output.active_target == "aws"
    error_message = "The runbook's DNS switch command must send all traffic to AWS."
  }
}

run "rejects_tagged_images" {
  command = plan

  variables {
    images = {
      web = "123456789012.dkr.ecr.us-east-1.amazonaws.com/harbor-web:latest"
      api = "123456789012.dkr.ecr.us-east-1.amazonaws.com/harbor-api@sha256:2222222222222222222222222222222222222222222222222222222222222222"
    }
  }

  expect_failures = [var.images]
}
