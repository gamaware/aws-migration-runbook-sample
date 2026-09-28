output "active_target" {
  description = "Side that receives traffic with the current weights: onprem or aws."
  value       = var.traffic_weights.aws == 100 ? "aws" : "onprem"
}

output "record_names" {
  description = "Names managed as weighted pairs."
  value       = sort(keys(var.records))
}

output "zone_id" {
  description = "ID of the private hosted zone; the break-glass change batch targets it (prerequisite P-03)."
  value       = aws_route53_zone.private.zone_id
}

output "resolver_inbound_ips" {
  description = "Addresses of the Resolver inbound endpoint that the corporate DNS servers forward the wave 1 names to."
  value       = sort([for a in aws_route53_resolver_endpoint.inbound.ip_address : a.ip])
}
