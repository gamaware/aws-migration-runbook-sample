mock_provider "aws" {
  source = "../../tests/mocks"
}

# Distinct ARNs per endpoint, so the wiring assertions below cannot pass by accident.
override_resource {
  target = aws_dms_endpoint.onprem_source
  values = { endpoint_arn = "arn:aws:dms:us-east-1:111122223333:endpoint:ONPREMSOURCE" }
}

override_resource {
  target = aws_dms_endpoint.rds_target
  values = { endpoint_arn = "arn:aws:dms:us-east-1:111122223333:endpoint:RDSTARGET" }
}

override_resource {
  target = aws_dms_endpoint.rds_source
  values = { endpoint_arn = "arn:aws:dms:us-east-1:111122223333:endpoint:RDSSOURCE" }
}

override_resource {
  target = aws_dms_endpoint.onprem_target
  values = { endpoint_arn = "arn:aws:dms:us-east-1:111122223333:endpoint:ONPREMTARGET" }
}

variables {
  name        = "hg-test"
  vpc_id      = "vpc-0123456789abcdef0"
  vpc_cidr    = "10.60.0.0/16"
  subnet_ids  = ["subnet-0bbbbbbbbbbbbbbb1", "subnet-0bbbbbbbbbbbbbbb2"]
  onprem_cidr = "10.40.0.0/16"
  kms_key_arn = "arn:aws:kms:us-east-1:111122223333:key/11111111-2222-3333-4444-555555555555"

  onprem_database = { server_name = "10.40.4.41", port = 5432, database_name = "harbor" }
  rds_database    = { server_name = "mock.abcdefghijkl.us-east-1.rds.amazonaws.com", port = 5432, database_name = "harbor" }

  # The same files Terraform deploys in production, so the tests fail if someone edits them into an unsafe shape.
  forward_task = {
    id             = "harbor-wave1-full-load-cdc"
    migration_type = "full-load-and-cdc"
    table_mappings = file("../../../../migration/dms/table-mappings.json")
    settings       = file("../../../../migration/dms/task-settings-forward.json")
  }
  reverse_task = {
    id             = "harbor-wave1-reverse-cdc"
    migration_type = "cdc"
    table_mappings = file("../../../../migration/dms/table-mappings.json")
    settings       = file("../../../../migration/dms/task-settings-reverse.json")
  }
}

run "forward_copies_then_streams_changes" {
  command = apply

  assert {
    condition     = aws_dms_replication_task.forward.migration_type == "full-load-and-cdc"
    error_message = "The forward task must run a full load followed by change data capture."
  }

  assert {
    condition     = aws_dms_replication_task.forward.source_endpoint_arn == aws_dms_endpoint.onprem_source.endpoint_arn && aws_dms_replication_task.forward.target_endpoint_arn == aws_dms_endpoint.rds_target.endpoint_arn
    error_message = "The forward task must read from the data center and write to RDS."
  }

  assert {
    condition     = jsondecode(aws_dms_replication_task.forward.replication_task_settings).ValidationSettings.EnableValidation
    error_message = "Row-level validation must be on for the forward task; go/no-go criterion G-03 depends on it."
  }
}

run "reverse_only_streams_changes_back" {
  command = apply

  assert {
    condition     = aws_dms_replication_task.reverse.migration_type == "cdc"
    error_message = "The reverse task must be change data capture only."
  }

  assert {
    condition     = aws_dms_replication_task.reverse.source_endpoint_arn == aws_dms_endpoint.rds_source.endpoint_arn && aws_dms_replication_task.reverse.target_endpoint_arn == aws_dms_endpoint.onprem_target.endpoint_arn
    error_message = "The reverse task must read from RDS and write to the data center."
  }
}

run "tasks_never_start_on_apply" {
  command = apply

  assert {
    condition     = !aws_dms_replication_task.forward.start_replication_task && !aws_dms_replication_task.reverse.start_replication_task
    error_message = "Only the runbook starts replication; a Terraform apply must not."
  }
}

run "request_log_is_excluded" {
  command = apply

  assert {
    condition = anytrue([
      for r in jsondecode(aws_dms_replication_task.forward.table_mappings).rules :
      r["rule-action"] == "exclude" && r["object-locator"]["schema-name"] == "audit" && r["object-locator"]["table-name"] == "request_log"
    ])
    error_message = "audit.request_log has no primary key and must be excluded from change data capture."
  }
}

run "credentials_stay_out_of_terraform" {
  command = apply

  assert {
    condition     = alltrue([for e in [aws_dms_endpoint.onprem_source, aws_dms_endpoint.rds_target, aws_dms_endpoint.rds_source, aws_dms_endpoint.onprem_target] : e.password == null && e.secrets_manager_arn != null && e.ssl_mode == "require"])
    error_message = "Endpoints must read credentials from Secrets Manager and require TLS."
  }

  assert {
    condition     = !aws_dms_replication_instance.this.publicly_accessible
    error_message = "The replication instance must not be public."
  }
}

run "rejects_full_load_only" {
  command = plan

  variables {
    forward_task = {
      id             = "harbor-wave1-full-load-cdc"
      migration_type = "full-load"
      table_mappings = file("../../../../migration/dms/table-mappings.json")
      settings       = file("../../../../migration/dms/task-settings-forward.json")
    }
  }

  expect_failures = [var.forward_task]
}

run "rejects_reverse_full_load" {
  command = plan

  variables {
    reverse_task = {
      id             = "harbor-wave1-reverse-cdc"
      migration_type = "full-load-and-cdc"
      table_mappings = file("../../../../migration/dms/table-mappings.json")
      settings       = file("../../../../migration/dms/task-settings-reverse.json")
    }
  }

  expect_failures = [var.reverse_task]
}

run "https_stays_inside_the_vpc" {
  command = apply

  assert {
    condition     = aws_vpc_security_group_egress_rule.to_aws_apis.cidr_ipv4 == var.vpc_cidr
    error_message = "The replication instance reaches Secrets Manager through its interface endpoint, never the internet."
  }

  assert {
    condition     = alltrue([for r in [aws_vpc_security_group_egress_rule.to_onprem_postgres, aws_vpc_security_group_egress_rule.to_rds_postgres, aws_vpc_security_group_egress_rule.to_aws_apis] : !contains(["0.0.0.0/0", "::/0"], coalesce(r.cidr_ipv4, r.cidr_ipv6, "none"))])
    error_message = "No DMS egress rule may reach 0.0.0.0/0 or ::/0."
  }
}
