data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

# --- Account-level service roles DMS expects under fixed names ------------------------------------------------

resource "aws_iam_role" "dms_vpc" {
  count = var.create_service_roles ? 1 : 0

  name = "dms-vpc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dms.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  count = var.create_service_roles ? 1 : 0

  role       = aws_iam_role.dms_vpc[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_role" "dms_cloudwatch" {
  count = var.create_service_roles ? 1 : 0

  name = "dms-cloudwatch-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dms.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch" {
  count = var.create_service_roles ? 1 : 0

  role       = aws_iam_role.dms_cloudwatch[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

# --- Credentials -----------------------------------------------------------------------------------------------

# Terraform creates the secret containers only. The DBA stores the values out of band (runbook prerequisite P-06),
# so no database password ever reaches Terraform state.
resource "aws_secretsmanager_secret" "onprem" {
  #checkov:skip=CKV2_AWS_57:The DMS user on the data center server is dropped at the end of hypercare; rotation would outlive it.
  name_prefix = "${var.name}/dms/onprem-"
  description = "DMS user on the data center PostgreSQL server (SRV-07)"
  kms_key_id  = var.kms_key_arn
}

resource "aws_secretsmanager_secret" "rds" {
  #checkov:skip=CKV2_AWS_57:The DMS user on RDS is dropped at the end of hypercare; rotation would outlive it.
  name_prefix = "${var.name}/dms/rds-"
  description = "DMS user on the RDS instance"
  kms_key_id  = var.kms_key_arn
}

resource "aws_iam_role" "secrets_access" {
  name = "${var.name}-dms-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dms.${data.aws_region.current.region}.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "secrets_access" {
  name = "read-dms-credentials"
  role = aws_iam_role.secrets_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = [aws_secretsmanager_secret.onprem.arn, aws_secretsmanager_secret.rds.arn]
      },
      {
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = var.kms_key_arn
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${data.aws_region.current.region}.amazonaws.com" } }
      },
    ]
  })
}

# --- Replication instance --------------------------------------------------------------------------------------

resource "aws_security_group" "dms" {
  name        = "${var.name}-dms"
  description = "DMS replication instance: PostgreSQL to the data center and to RDS, HTTPS to Secrets Manager"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "to_onprem_postgres" {
  security_group_id = aws_security_group.dms.id
  description       = "PostgreSQL in the data center over the VPN"
  cidr_ipv4         = var.onprem_cidr
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "to_rds_postgres" {
  security_group_id = aws_security_group.dms.id
  description       = "PostgreSQL on RDS inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "to_aws_apis" {
  security_group_id = aws_security_group.dms.id
  description       = "HTTPS to Secrets Manager and CloudWatch through NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = var.name
  replication_subnet_group_description = "Application subnets with routes to the data center"
  subnet_ids                           = var.subnet_ids

  depends_on = [aws_iam_role_policy_attachment.dms_vpc]
}

# Multi-AZ keeps change data capture running if one Availability Zone fails during the weeks between the full
# load and cutover; the instance is deleted after hypercare, so the extra cost is bounded.
resource "aws_dms_replication_instance" "this" {
  replication_instance_id     = var.name
  replication_instance_class  = var.instance_class
  allocated_storage           = var.allocated_storage_gb
  multi_az                    = true
  publicly_accessible         = false
  kms_key_arn                 = var.kms_key_arn
  auto_minor_version_upgrade  = true
  replication_subnet_group_id = aws_dms_replication_subnet_group.this.id
  vpc_security_group_ids      = [aws_security_group.dms.id]
}

# --- Endpoints -------------------------------------------------------------------------------------------------

# TLS without certificate verification (ssl_mode require). verify-full needs the RDS CA bundle and the data center
# CA imported as DMS certificates; that hardening is tracked as report RISK-09.
resource "aws_dms_endpoint" "onprem_source" {
  endpoint_id                     = "${var.name}-onprem-source"
  endpoint_type                   = "source"
  engine_name                     = "postgres"
  database_name                   = var.onprem_database.database_name
  ssl_mode                        = "require"
  kms_key_arn                     = var.kms_key_arn
  secrets_manager_arn             = aws_secretsmanager_secret.onprem.arn
  secrets_manager_access_role_arn = aws_iam_role.secrets_access.arn

  postgres_settings {
    plugin_name      = "test-decoding"
    heartbeat_enable = true
  }
}

resource "aws_dms_endpoint" "rds_target" {
  endpoint_id                     = "${var.name}-rds-target"
  endpoint_type                   = "target"
  engine_name                     = "postgres"
  database_name                   = var.rds_database.database_name
  ssl_mode                        = "require"
  kms_key_arn                     = var.kms_key_arn
  secrets_manager_arn             = aws_secretsmanager_secret.rds.arn
  secrets_manager_access_role_arn = aws_iam_role.secrets_access.arn

  postgres_settings {
    after_connect_script = "SET session_replication_role = replica"
  }
}

resource "aws_dms_endpoint" "rds_source" {
  endpoint_id                     = "${var.name}-rds-source"
  endpoint_type                   = "source"
  engine_name                     = "postgres"
  database_name                   = var.rds_database.database_name
  ssl_mode                        = "require"
  kms_key_arn                     = var.kms_key_arn
  secrets_manager_arn             = aws_secretsmanager_secret.rds.arn
  secrets_manager_access_role_arn = aws_iam_role.secrets_access.arn

  postgres_settings {
    plugin_name      = "test-decoding"
    heartbeat_enable = true
  }
}

resource "aws_dms_endpoint" "onprem_target" {
  endpoint_id                     = "${var.name}-onprem-target"
  endpoint_type                   = "target"
  engine_name                     = "postgres"
  database_name                   = var.onprem_database.database_name
  ssl_mode                        = "require"
  kms_key_arn                     = var.kms_key_arn
  secrets_manager_arn             = aws_secretsmanager_secret.onprem.arn
  secrets_manager_access_role_arn = aws_iam_role.secrets_access.arn

  postgres_settings {
    after_connect_script = "SET session_replication_role = replica"
  }
}

# --- Tasks -----------------------------------------------------------------------------------------------------

# Neither task starts on apply. The runbook starts the forward task at T-7d (full load) and the reverse task at the
# DNS switch, each with an explicit command, so a Terraform run can never kick off a replication by accident.
resource "aws_dms_replication_task" "forward" {
  replication_task_id       = var.forward_task.id
  migration_type            = var.forward_task.migration_type
  replication_instance_arn  = aws_dms_replication_instance.this.replication_instance_arn
  source_endpoint_arn       = aws_dms_endpoint.onprem_source.endpoint_arn
  target_endpoint_arn       = aws_dms_endpoint.rds_target.endpoint_arn
  table_mappings            = var.forward_task.table_mappings
  replication_task_settings = var.forward_task.settings
  start_replication_task    = false

  # DMS fills in defaults for every setting the JSON leaves out, which Terraform would report as drift on each
  # plan. A settings change therefore goes through `aws dms modify-replication-task` in the runbook, not an apply.
  lifecycle {
    ignore_changes = [replication_task_settings]
  }
}

resource "aws_dms_replication_task" "reverse" {
  replication_task_id       = var.reverse_task.id
  migration_type            = var.reverse_task.migration_type
  replication_instance_arn  = aws_dms_replication_instance.this.replication_instance_arn
  source_endpoint_arn       = aws_dms_endpoint.rds_source.endpoint_arn
  target_endpoint_arn       = aws_dms_endpoint.onprem_target.endpoint_arn
  table_mappings            = var.reverse_task.table_mappings
  replication_task_settings = var.reverse_task.settings
  start_replication_task    = false

  lifecycle {
    ignore_changes = [replication_task_settings]
  }
}
