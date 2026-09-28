# Module: app

Internal Application Load Balancer and two ECS Fargate services (the warehouse web app and the inventory API) that
replace the HAProxy pair and four application servers. The load balancer sits in private subnets and admits only the
RFC 1918 client ranges it is given (the corporate network over the VPN, the peered storefront VPC and the VPC itself).
Task HTTPS egress reaches the VPC (interface endpoints and the load balancer), S3 through the gateway endpoint prefix
list and the parcel carrier's published addresses; no rule opens `0.0.0.0/0`. Access logs go to the central log
archive bucket, because ALB access logging supports only SSE-S3 (ADR 0006). Port 80 redirects to HTTPS, tasks run as
a non-root user on a read-only file system, images must be pinned by digest, and deployments roll back on their own.
Tests: `tests/app.tftest.hcl`.

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
| [aws_cloudwatch_log_group.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_service.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.execution_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_rule.host](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.alb_to_services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.services_https_carrier](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.services_https_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.services_https_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.services_postgres](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.alb_http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.alb_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.services_from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| access\_logs | Central log archive bucket and prefix for the load balancer access logs. The bucket policy must allow the Elastic Load Balancing log delivery service. | ```object({ bucket = string prefix = string })``` | n/a | yes |
| alb\_ingress\_cidrs | Private client ranges allowed to reach the internal load balancer: the corporate network, peered VPCs and the VPC itself. | `list(string)` | n/a | yes |
| alb\_subnet\_ids | Private subnets for the internal Application Load Balancer, one per Availability Zone. | `list(string)` | n/a | yes |
| app\_subnet\_ids | Private subnets for the ECS tasks. | `list(string)` | n/a | yes |
| certificate\_arn | ACM certificate for the HTTPS listener. It must cover every host name in var.services. | `string` | n/a | yes |
| kms\_key\_arn | KMS key that encrypts the container log groups. | `string` | n/a | yes |
| name | Name prefix for every resource in the module. | `string` | n/a | yes |
| s3\_prefix\_list\_id | Prefix list of the S3 gateway endpoint; the tasks pull ECR image layers from S3 through it. | `string` | n/a | yes |
| services | ECS services keyed by name. Each one replaces the source servers listed in plan/target.yaml. | ```map(object({ image = string cpu = number memory = number desired_count = number container_port = number health_check_path = string host_name = string environment = optional(map(string), {}) secrets = optional(map(string), {}) }))``` | n/a | yes |
| vpc\_cidr | CIDR block of the VPC; tasks reach the database, the interface endpoints and the load balancer only inside it. | `string` | n/a | yes |
| vpc\_id | VPC that hosts the load balancer and the ECS services. | `string` | n/a | yes |
| carrier\_api\_cidrs | Published addresses of the parcel carrier label API, reached through the NAT gateways. | `list(string)` | `[]` | no |
| default\_service | Service that receives requests whose host name matches no rule. | `string` | `"web"` | no |
| log\_retention\_days | Retention of the container log groups in days. | `number` | `365` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alb\_arn\_suffix | ARN suffix of the load balancer, used in CloudWatch metric queries during cutover. |
| alb\_dns\_name | DNS name of the internal load balancer; the aws records in the private hosted zones alias to it. |
| alb\_zone\_id | Hosted zone ID of the load balancer, needed for alias records. |
| cluster\_name | Name of the ECS cluster. |
| network\_exposure | What can reach the load balancer and where the tasks may connect; the tests assert none of it is the internet. |
| service\_names | ECS service names keyed by service. |
| service\_security\_group\_id | Security group of the ECS tasks; the database admits it on 5432. |
<!-- END_TF_DOCS -->
