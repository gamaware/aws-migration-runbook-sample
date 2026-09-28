# Live test root: the smallest slice of the wave 1 target that proves the parts a mock cannot. AWS must accept the
# VPN tunnel options, create PostgreSQL 16 with logical replication on, and keep the database private. Everything
# carries purpose=portfolio-test; scripts/test_live.sh applies the checked plan, asserts, destroys and checks
# that no tagged resource is left.
#
# Private-only (ADR 0005): the network module runs with internet_egress = false, so the run creates no internet
# gateway, public subnet, NAT gateway, Elastic IP or default route. The only path out of the VPC is the VPN to the
# on-premises CIDR. infra/terraform/tests/live_private asserts this offline, and scripts/test_live.sh refuses to run
# when scripts/check_private_plan.py finds an internet-facing resource in the plan.

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = merge(var.extra_tags, {
      purpose = "portfolio-test"
      project = "aws-migration-runbook-sample"
      run     = var.run_id
    })
  }
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "live" {
  description             = "Live test key for aws-migration-runbook-sample (${var.run_id})"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${var.region}.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
      },
    ]
  })
}

module "network" {
  source = "../../modules/network"

  name        = "hg-live-${var.run_id}"
  vpc_cidr    = "10.60.0.0/16"
  azs         = ["${var.region}a", "${var.region}b"]
  onprem_cidr = "10.40.0.0/16"
  vpn_peer_ip = "203.0.113.20"
  vpn_bgp_asn = 65010
  kms_key_arn = aws_kms_key.live.arn

  internet_egress = false
}

module "database" {
  source = "../../modules/database"

  name                      = "hg-live-${var.run_id}"
  vpc_id                    = module.network.vpc_id
  data_subnet_ids           = module.network.data_subnet_ids
  engine_version            = "16"
  instance_class            = "db.t4g.medium"
  allocated_storage_gb      = 20
  max_allocated_storage_gb  = 40
  multi_az                  = false
  backup_retention_days     = 7
  kms_key_arn               = aws_kms_key.live.arn
  client_security_group_ids = []
  onprem_client_cidrs       = ["10.40.3.51/32"]
  deletion_protection       = false
  skip_final_snapshot       = true
}
