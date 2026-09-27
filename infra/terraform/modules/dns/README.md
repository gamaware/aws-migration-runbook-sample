# Module: dns

Route 53 weighted record pairs for each name that moves in wave 1. The `onprem` member points at the data center
address and the `aws` member aliases the load balancer. Weights are 100/0 or 0/100 only, because the database has
one writer (ADR 0003). Tests: `tests/dns.tftest.hcl`.

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

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| alb\_dns\_name | DNS name of the load balancer the aws records alias to. | `string` | n/a | yes |
| alb\_zone\_id | Hosted zone ID of the load balancer. | `string` | n/a | yes |
| records | Records to switch, keyed by fully qualified name, with the on-premises address they point to today. | ```map(object({ onprem_ip = string }))``` | n/a | yes |
| zone\_id | Route 53 hosted zone that holds the records (example.com). | `string` | n/a | yes |
| onprem\_ttl | TTL of the on-premises records. Low, so a switch or a rollback reaches clients within minutes. | `number` | `60` | no |
| traffic\_weights | Route 53 weights. The database has one writer, so exactly one side receives traffic (ADR 0003). | ```object({ onprem = number aws = number })``` | ```{ "aws": 0, "onprem": 100 }``` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| active\_target | Side that receives traffic with the current weights: onprem or aws. |
| record\_names | Names managed as weighted pairs. |
<!-- END_TF_DOCS -->
