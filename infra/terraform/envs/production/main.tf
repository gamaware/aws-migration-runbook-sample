# Wave 1 target environment for Harbor Goods. Sizes, addresses, task identifiers and the on-premises hosts that
# may reach the database all come from plan/ and data/synthetic/, the same files scripts/check_plan.py validates.

locals {
  repo_root = "${path.module}/../../../.."

  target         = yamldecode(file("${local.repo_root}/plan/target.yaml"))
  waves          = yamldecode(file("${local.repo_root}/plan/waves.yaml"))
  data_migration = yamldecode(file("${local.repo_root}/plan/data-migration.yaml"))
  servers        = { for s in csvdecode(file("${local.repo_root}/data/synthetic/servers.csv")) : s.server_id => s }

  name      = "harbor-prod"
  db_source = local.servers[local.target.database.source]

  # Hosts that stay on premises after wave 1 but read or write the database: the hybrid links in the plan.
  db_hybrid_clients = sort([
    for l in local.waves.hybrid_links : "${local.servers[l.consumer].private_ip}/32"
    if l.provider == local.target.database.source
  ])

  hostnames = [for r in local.target.records : r.name]
  services = {
    for name, s in local.target.services : name => {
      image             = var.images[name]
      cpu               = s.cpu
      memory            = s.memory
      desired_count     = s.desired_count
      container_port    = s.container_port
      health_check_path = s.health_check_path
      host_name         = one([for r in local.target.records : r.name if r.service == name])
      environment       = name == "api" ? { DB_HOST = module.database.address, DB_NAME = "harbor" } : { API_BASE_URL = "https://api.${local.target.hosted_zone}" }
      secrets           = name == "api" ? { DB_CREDENTIALS = aws_secretsmanager_secret.app_db.arn } : {}
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# The public zone serves one purpose here: the ACM DNS validation records, which prove control of the names to the
# certificate authority. They are CNAMEs to acm-validations.aws, not endpoints; the names users resolve live in the
# private hosted zones of the dns module and never point at anything public.
data "aws_route53_zone" "public" {
  name         = local.target.hosted_zone
  private_zone = false
}

# --- Encryption ------------------------------------------------------------------------------------------------

resource "aws_kms_key" "this" {
  description             = "Harbor Goods production: RDS, DMS, secrets and log groups"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.target.region}.amazonaws.com" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:${local.target.region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}

# Application database credentials. The DBA creates the role on RDS (manual step M-04) and stores the value here.
resource "aws_secretsmanager_secret" "app_db" {
  #checkov:skip=CKV2_AWS_57:Rotation needs the application to reload credentials; it is scheduled after hypercare (report RISK-08).
  name_prefix = "${local.name}/app-db-"
  description = "Inventory API database user on RDS"
  kms_key_id  = aws_kms_key.this.arn
}

# --- TLS certificate for the wave 1 host names -----------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  domain_name               = local.hostnames[0]
  subject_alternative_names = slice(local.hostnames, 1, length(local.hostnames))
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Keyed by the host names from the plan, which are known at plan time, rather than by the certificate's
# validation options, which are not.
resource "aws_route53_record" "certificate_validation" {
  for_each = toset(local.hostnames)

  zone_id         = data.aws_route53_zone.public.zone_id
  name            = one([for o in aws_acm_certificate.this.domain_validation_options : o.resource_record_name if o.domain_name == each.key])
  type            = one([for o in aws_acm_certificate.this.domain_validation_options : o.resource_record_type if o.domain_name == each.key])
  records         = [one([for o in aws_acm_certificate.this.domain_validation_options : o.resource_record_value if o.domain_name == each.key])]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.certificate_validation : r.fqdn]
}

# --- Modules ---------------------------------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  name        = local.name
  vpc_cidr    = local.target.vpc_cidr
  azs         = local.target.availability_zones
  onprem_cidr = local.target.onprem_cidr
  vpn_peer_ip = local.target.onprem_vpn_peer_ip
  vpn_bgp_asn = local.target.onprem_bgp_asn
  kms_key_arn = aws_kms_key.this.arn

  storefront_vpc = local.target.storefront_vpc
}

module "app" {
  source = "../../modules/app"

  name              = local.name
  vpc_id            = module.network.vpc_id
  vpc_cidr          = module.network.vpc_cidr
  alb_subnet_ids    = module.network.app_subnet_ids
  app_subnet_ids    = module.network.app_subnet_ids
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn
  kms_key_arn       = aws_kms_key.this.arn
  services          = local.services
  s3_prefix_list_id = module.network.s3_prefix_list_id
  carrier_api_cidrs = local.target.carrier_api_cidrs
  access_logs       = local.target.alb_access_logs

  # Warehouse staff on the corporate network (over the VPN), the storefront VPC (peered) and the web tasks.
  alb_ingress_cidrs = sort(distinct([local.target.onprem_cidr, local.target.storefront_vpc.cidr, module.network.vpc_cidr]))
}

module "database" {
  source = "../../modules/database"

  name                      = local.name
  vpc_id                    = module.network.vpc_id
  data_subnet_ids           = module.network.data_subnet_ids
  engine_version            = local.target.database.engine_version
  instance_class            = local.target.database.instance_class
  allocated_storage_gb      = local.target.database.allocated_storage_gb
  max_allocated_storage_gb  = local.target.database.max_allocated_storage_gb
  multi_az                  = local.target.database.multi_az
  backup_retention_days     = local.target.database.backup_retention_days
  kms_key_arn               = aws_kms_key.this.arn
  client_security_group_ids = [module.app.service_security_group_id, module.dms.security_group_id]
  onprem_client_cidrs       = local.db_hybrid_clients
}

module "dms" {
  source = "../../modules/dms"

  name                 = local.name
  vpc_id               = module.network.vpc_id
  vpc_cidr             = module.network.vpc_cidr
  subnet_ids           = module.network.app_subnet_ids
  onprem_cidr          = local.target.onprem_cidr
  kms_key_arn          = aws_kms_key.this.arn
  create_service_roles = var.create_dms_service_roles

  onprem_database = { server_name = local.db_source.private_ip, port = 5432, database_name = "harbor" }
  rds_database    = { server_name = module.database.address, port = module.database.port, database_name = "harbor" }

  forward_task = {
    id             = local.data_migration.tasks.forward.id
    migration_type = local.data_migration.tasks.forward.migration_type
    table_mappings = file("${local.repo_root}/${local.data_migration.tasks.forward.table_mappings}")
    settings       = file("${local.repo_root}/${local.data_migration.tasks.forward.settings}")
  }
  reverse_task = {
    id             = local.data_migration.tasks.reverse.id
    migration_type = local.data_migration.tasks.reverse.migration_type
    table_mappings = file("${local.repo_root}/${local.data_migration.tasks.reverse.table_mappings}")
    settings       = file("${local.repo_root}/${local.data_migration.tasks.reverse.settings}")
  }
}

module "dns" {
  source = "../../modules/dns"

  name                  = local.name
  vpc_id                = module.network.vpc_id
  associated_vpc_ids    = [local.target.storefront_vpc.id]
  resolver_subnet_ids   = module.network.app_subnet_ids
  resolver_client_cidrs = [local.target.onprem_cidr]

  records         = { for r in local.target.records : r.name => { onprem_ip = r.onprem_value } }
  alb_dns_name    = module.app.alb_dns_name
  alb_zone_id     = module.app.alb_zone_id
  traffic_weights = var.traffic_weights
}
