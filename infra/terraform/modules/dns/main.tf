# Each name is a weighted pair: "onprem" points at the data center address, "aws" aliases the load balancer.
# The cutover changes only the weights. Terraform updates the two members in separate calls, so for a few seconds
# both sides may answer; that is harmless because the data center serves only the maintenance page while writes
# are frozen. The break-glass rollback in the runbook flips both weights in one Route 53 change batch instead.

resource "aws_route53_record" "onprem" {
  #checkov:skip=CKV2_AWS_23:The record points at the data center address on purpose; it is removed when wave 1 exits.
  for_each = var.records

  zone_id        = var.zone_id
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

  zone_id        = var.zone_id
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
