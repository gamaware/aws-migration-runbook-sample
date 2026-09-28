mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  name                      = "hg-test"
  vpc_id                    = "vpc-0123456789abcdef0"
  data_subnet_ids           = ["subnet-0ccccccccccccccc1", "subnet-0ccccccccccccccc2"]
  engine_version            = "16"
  instance_class            = "db.r7g.2xlarge"
  allocated_storage_gb      = 400
  max_allocated_storage_gb  = 1000
  kms_key_arn               = "arn:aws:kms:us-east-1:111122223333:key/11111111-2222-3333-4444-555555555555"
  client_security_group_ids = ["sg-0aaaaaaaaaaaaaaa1", "sg-0aaaaaaaaaaaaaaa2"]
  onprem_client_cidrs       = ["10.40.3.51/32", "10.40.5.61/32"]
}

run "database_is_private_encrypted_and_multi_az" {
  command = apply

  assert {
    condition     = !aws_db_instance.this.publicly_accessible && aws_db_instance.this.storage_encrypted && aws_db_instance.this.multi_az
    error_message = "The database must be private, encrypted and Multi-AZ."
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection && !aws_db_instance.this.skip_final_snapshot
    error_message = "Deletion protection and a final snapshot guard against an accidental destroy during hypercare."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password && aws_db_instance.this.password == null
    error_message = "RDS must manage the master password in Secrets Manager; Terraform state must never hold it."
  }
}

run "reverse_replication_is_possible" {
  command = apply

  assert {
    condition     = one([for p in aws_db_parameter_group.this.parameter : p.value if p.name == "rds.logical_replication"]) == "1"
    error_message = "rds.logical_replication must be on, or the reverse DMS task (rollback path) cannot read changes from RDS."
  }

  assert {
    condition     = one([for p in aws_db_parameter_group.this.parameter : p.value if p.name == "rds.force_ssl"]) == "1"
    error_message = "Clients, including DMS over the VPN, must use TLS."
  }
}

run "onprem_access_is_limited_to_listed_hosts" {
  command = apply

  assert {
    condition     = join(",", output.onprem_client_cidrs) == "10.40.3.51/32,10.40.5.61/32"
    error_message = "Only the hosts from the plan's hybrid links may reach the database from the data center."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_security_groups) == 2
    error_message = "Each AWS client security group gets its own rule."
  }
}

run "rejects_short_backup_retention" {
  command = plan

  variables {
    backup_retention_days = 3
  }

  expect_failures = [var.backup_retention_days]
}

run "rejects_a_whole_onprem_range" {
  command = plan

  variables {
    onprem_client_cidrs = ["10.40.0.0/16"]
  }

  expect_failures = [var.onprem_client_cidrs]
}

run "rejects_a_minor_version_pin" {
  command = plan

  variables {
    engine_version = "16.4"
  }

  expect_failures = [var.engine_version]
}

run "rejects_autoscaling_ceiling_at_or_below_allocation" {
  command = plan

  variables {
    max_allocated_storage_gb = 400
  }

  expect_failures = [var.max_allocated_storage_gb]
}
