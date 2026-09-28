data "aws_caller_identity" "current" {}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.data_subnet_ids
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "PostgreSQL: ECS tasks, DMS and the on-premises hosts listed in the hybrid links"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  count = length(var.client_security_group_ids)

  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from an AWS client security group"
  referenced_security_group_id = var.client_security_group_ids[count.index]
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "from_onprem" {
  for_each = toset(var.onprem_client_cidrs)

  security_group_id = aws_security_group.db.id
  description       = "PostgreSQL from an on-premises host over the VPN"
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

# rds.logical_replication lets the reverse DMS task read changes from RDS, which is what makes a rollback after
# the DNS switch possible without losing orders written on AWS.
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-pg${var.engine_version}-"
  family      = "postgres${var.engine_version}"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "monitoring" {
  name = "${var.name}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  db_name        = "harbor"

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  username                            = "harbor_admin"
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = var.kms_key_arn
  iam_database_authentication_enabled = true

  multi_az               = var.multi_az
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period   = var.backup_retention_days
  backup_window             = "05:00-06:00"
  maintenance_window        = "sun:08:00-sun:09:00"
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final"

  auto_minor_version_upgrade            = true
  allow_major_version_upgrade           = false
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
}
