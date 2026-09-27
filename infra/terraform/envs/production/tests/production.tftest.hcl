# Composition tests: they prove that the numbers and identifiers in plan/ reach the resources, which is what the
# runbook and the report rely on. No AWS account is involved.
mock_provider "aws" {
  source = "../../tests/mocks"
}

override_data {
  target = data.aws_route53_zone.this
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
