# The wave 1 names live in a Route 53 private hosted zone, because the load balancer they switch to is internal. The
# zone is associated with the wave 1 VPC and the storefront VPC; the corporate resolvers reach it over the VPN through
# the Resolver inbound endpoint below. Nothing here is published on the internet.
#
# Each name is a weighted pair: "onprem" points at the data center address, "aws" aliases the load balancer.
# The cutover changes only the weights. Terraform updates the two members in separate calls, so for a few seconds
# both sides may answer; that is harmless because the data center serves only the maintenance page while writes
# are frozen. The break-glass rollback in the runbook flips both weights in one Route 53 change batch instead.

resource "aws_route53_record" "onprem" {
  #checkov:skip=CKV2_AWS_23:The record points at the data center address on purpose; it is removed when wave 1 exits.
  for_each = var.records

  zone_id        = aws_route53_zone.private.zone_id
  name           = each.key
  type           = "A"
  ttl            = var.onprem_ttl
  records        = [each.value.onprem_ip]
  set_identifier = "onprem"

  weighted_routing_policy {
    weight = var.traffic_weights.onprem
  }
}

resource "aws_route53_record" "aws" {
  for_each = var.records

  zone_id        = aws_route53_zone.private.zone_id
  name           = each.key
  type           = "A"
  set_identifier = "aws"

  alias {
    name    = var.alb_dns_name
    zone_id = var.alb_zone_id
    # false: with a 0/100 pair, Route 53 would answer with the zero-weight onprem member if the load balancer
    # looked unhealthy, silently sending writes back to the data center. A failback is a decision (rollback R-03).
    evaluate_target_health = false
  }

  weighted_routing_policy {
    weight = var.traffic_weights.aws
  }
}

# --- Private hosted zone ---------------------------------------------------------------------------------------

resource "aws_route53_zone" "private" {
  name    = var.zone_name
  comment = "Wave 1 names, resolvable only inside the associated VPCs and through the Resolver inbound endpoint"

  vpc {
    vpc_id = var.vpc_id
  }

  dynamic "vpc" {
    for_each = toset(var.associated_vpc_ids)

    content {
      vpc_id = vpc.value
    }
  }
}

# --- Resolver inbound endpoint ---------------------------------------------------------------------------------

# The corporate DNS servers forward the wave 1 names to these addresses (runbook step C-02), so staff on the
# corporate network resolve the private zone over the Site-to-Site VPN.
resource "aws_security_group" "resolver" {
  name        = "${var.name}-resolver-inbound"
  description = "Route 53 Resolver inbound endpoint: DNS from the corporate network only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "resolver" {
  for_each = { for pair in setproduct(var.resolver_client_cidrs, ["tcp", "udp"]) : "${pair[0]}-${pair[1]}" => pair }

  security_group_id = aws_security_group.resolver.id
  description       = "DNS over ${upper(each.value[1])} from ${each.value[0]}"
  cidr_ipv4         = each.value[0]
  from_port         = 53
  to_port           = 53
  ip_protocol       = each.value[1]
}

resource "aws_route53_resolver_endpoint" "inbound" {
  name               = "${var.name}-inbound"
  direction          = "INBOUND"
  security_group_ids = [aws_security_group.resolver.id]
  protocols          = ["Do53"]

  dynamic "ip_address" {
    for_each = toset(var.resolver_subnet_ids)

    content {
      subnet_id = ip_address.value
    }
  }
}
