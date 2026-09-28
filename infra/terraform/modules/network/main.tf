data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  az_count = length(var.azs)

  # One /24 per tier per Availability Zone: public from .0, application from .10, data from .20.
  public_cidrs = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 24 - tonumber(split("/", var.vpc_cidr)[1]), i)]
  app_cidrs    = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 24 - tonumber(split("/", var.vpc_cidr)[1]), 10 + i)]
  data_cidrs   = [for i in range(local.az_count) : cidrsubnet(var.vpc_cidr, 24 - tonumber(split("/", var.vpc_cidr)[1]), 20 + i)]

  # Without internet egress the module creates no internet gateway, public subnets, NAT gateways, Elastic IPs or
  # default routes: the VPC reaches only the data center over the VPN. The live test uses it that way.
  public_count = var.internet_egress ? local.az_count : 0
  igw_count    = var.internet_egress ? 1 : 0
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

# The default security group allows nothing, so a resource launched without an explicit group is isolated.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_internet_gateway" "this" {
  count = local.igw_count

  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

resource "aws_subnet" "public" {
  count = local.public_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public-${var.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "app" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.app_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-app-${var.azs[count.index]}", Tier = "app" }
}

resource "aws_subnet" "data" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.data_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-data-${var.azs[count.index]}", Tier = "data" }
}

# One NAT gateway per Availability Zone. Their Elastic IPs are the new source addresses the parcel carrier must
# allowlist before cutover (runbook prerequisite P-04).
resource "aws_eip" "nat" {
  count = local.public_count

  domain = "vpc"

  tags = { Name = "${var.name}-nat-${var.azs[count.index]}" }
}

resource "aws_nat_gateway" "this" {
  count = local.public_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = { Name = "${var.name}-${var.azs[count.index]}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  count = local.igw_count

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  count = local.igw_count

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count = local.public_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# The internet gateway and the public route table gained a count for the private-only mode; existing state moves.
moved {
  from = aws_internet_gateway.this
  to   = aws_internet_gateway.this[0]
}

moved {
  from = aws_route_table.public
  to   = aws_route_table.public[0]
}

moved {
  from = aws_route.public_internet
  to   = aws_route.public_internet[0]
}

resource "aws_route_table" "app" {
  count = local.az_count

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-app-${var.azs[count.index]}" }
}

resource "aws_route" "app_internet" {
  count = local.public_count

  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "app" {
  count = local.az_count

  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# Data subnets have no internet route. They reach the data center only through the VPN routes propagated below.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-data" }
}

resource "aws_route_table_association" "data" {
  count = local.az_count

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# Site-to-Site VPN to the data center. It carries the DMS replication traffic during the migration and the hybrid
# links listed in plan/waves.yaml afterwards.
resource "aws_vpn_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

resource "aws_customer_gateway" "onprem" {
  bgp_asn    = var.vpn_bgp_asn
  ip_address = var.vpn_peer_ip
  type       = "ipsec.1"

  tags = { Name = "${var.name}-onprem" }
}

resource "aws_vpn_connection" "onprem" {
  vpn_gateway_id      = aws_vpn_gateway.this.id
  customer_gateway_id = aws_customer_gateway.onprem.id
  type                = "ipsec.1"
  static_routes_only  = true

  # AWS generates the tunnel keys and keeps them in Secrets Manager, so they never land in Terraform state.
  preshared_key_storage = "SecretsManager"

  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256-GCM-16"]
  tunnel1_phase1_integrity_algorithms  = ["SHA2-384"]
  tunnel1_phase1_dh_group_numbers      = [20]
  tunnel1_phase2_encryption_algorithms = ["AES256-GCM-16"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-384"]
  tunnel1_phase2_dh_group_numbers      = [20]

  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_encryption_algorithms = ["AES256-GCM-16"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-384"]
  tunnel2_phase1_dh_group_numbers      = [20]
  tunnel2_phase2_encryption_algorithms = ["AES256-GCM-16"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-384"]
  tunnel2_phase2_dh_group_numbers      = [20]

  tags = { Name = "${var.name}-onprem" }
}

resource "aws_vpn_connection_route" "onprem" {
  vpn_connection_id      = aws_vpn_connection.onprem.id
  destination_cidr_block = var.onprem_cidr
}

resource "aws_vpn_gateway_route_propagation" "app" {
  count = local.az_count

  vpn_gateway_id = aws_vpn_gateway.this.id
  route_table_id = aws_route_table.app[count.index].id
}

resource "aws_vpn_gateway_route_propagation" "data" {
  vpn_gateway_id = aws_vpn_gateway.this.id
  route_table_id = aws_route_table.data.id
}

# --- VPC endpoints ---------------------------------------------------------------------------------------------

# AWS API calls from the tasks and the DMS instance stay inside the VPC, so their security groups need no internet
# egress. The S3 gateway endpoint is free and carries ECR image layers; its prefix list is what the task security
# group allows for S3. The live test passes an empty interface list and keeps only the gateway endpoint.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.app[*].id, [aws_route_table.data.id])

  tags = { Name = "${var.name}-s3" }
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-endpoints"
  description = "Interface VPC endpoints: HTTPS from inside the VPC only"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from the VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.name}-${each.value}" }
}

# --- Storefront VPC peering ------------------------------------------------------------------------------------

# The storefront VPC (same account) calls the inventory API on the internal load balancer. The storefront team adds
# the return route to this VPC's CIDR in their own route tables (runbook prerequisite P-02).
resource "aws_vpc_peering_connection" "storefront" {
  count = var.storefront_vpc == null ? 0 : 1

  vpc_id      = aws_vpc.this.id
  peer_vpc_id = var.storefront_vpc.id
  auto_accept = true

  tags = { Name = "${var.name}-storefront" }
}

resource "aws_route" "app_to_storefront" {
  count = var.storefront_vpc == null ? 0 : local.az_count

  route_table_id            = aws_route_table.app[count.index].id
  destination_cidr_block    = var.storefront_vpc.cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.storefront[0].id
}

# VPC flow logs: the first place to look when a hybrid link or the DMS source endpoint stops connecting.
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "write-flow-logs"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn    = aws_iam_role.flow_logs.arn
}
