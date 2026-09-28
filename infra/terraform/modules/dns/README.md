# Module: dns

One Route 53 private hosted zone per name that moves in wave 1, each holding a weighted record pair at its apex, and a
Resolver inbound endpoint that lets the corporate DNS servers resolve those zones over the VPN. A zone per name, rather
than one private `example.com` zone, keeps every other `example.com` name resolving publicly in the associated VPCs.
The `onprem` member points at the data center address and the `aws` member aliases the internal load balancer.
Weights are 100/0 or 0/100 only, because the database has one writer (ADR 0003); the zones are private because the
load balancer is internal (ADR 0006). Tests: `tests/dns.tftest.hcl`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11.0, < 2.0.0 |
| aws | >= 6.0, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 6.0, < 7.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_route53_record.aws](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.onprem](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_resolver_endpoint.inbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_zone.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |
| [aws_security_group.resolver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.resolver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| alb\_dns\_name | DNS name of the internal load balancer the aws records alias to. | `string` | n/a | yes |
| alb\_zone\_id | Hosted zone ID of the load balancer. | `string` | n/a | yes |
| name | Name prefix for the Resolver endpoint and its security group. | `string` | n/a | yes |
| records | Records to switch, keyed by fully qualified name, with the on-premises address they point to today. Each name gets its own private hosted zone. | ```map(object({ onprem_ip = string }))``` | n/a | yes |
| resolver\_client\_cidrs | Networks whose DNS servers forward the wave 1 names to the Resolver inbound endpoint (the corporate network). | `list(string)` | n/a | yes |
| resolver\_subnet\_ids | Private subnets for the Resolver inbound endpoint, in at least two Availability Zones. | `list(string)` | n/a | yes |
| vpc\_id | VPC that hosts the internal load balancer and the Resolver inbound endpoint; the private zones are associated with it. | `string` | n/a | yes |
| associated\_vpc\_ids | Other VPCs in the account that must resolve the records, such as the storefront VPC. | `list(string)` | `[]` | no |
| onprem\_ttl | TTL of the on-premises records. Low, so a switch or a rollback reaches clients within minutes. | `number` | `60` | no |
| traffic\_weights | Route 53 weights. The database has one writer, so exactly one side receives traffic (ADR 0003). | ```object({ onprem = number aws = number })``` | ```{ "aws": 0, "onprem": 100 }``` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| active\_target | Side that receives traffic with the current weights: onprem or aws. |
| record\_names | Names managed as weighted pairs. |
| resolver\_inbound\_ips | Addresses of the Resolver inbound endpoint that the corporate DNS servers forward the wave 1 names to. |
| zone\_ids | ID of the private hosted zone of each name; the break-glass change batches target them (prerequisite P-03). |
<!-- END_TF_DOCS -->
