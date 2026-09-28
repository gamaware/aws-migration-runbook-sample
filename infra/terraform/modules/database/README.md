# Module: database

Amazon RDS for PostgreSQL, Multi-AZ, encrypted with KMS, with the master password managed by RDS in Secrets
Manager. Logical replication is on so the reverse DMS task can read changes from RDS, which is the rollback path
after the DNS switch. On-premises clients are limited to single hosts. Tests: `tests/database.tftest.hcl`.

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
| [aws_db_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_role.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.from_onprem](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_security_groups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| allocated\_storage\_gb | Initial gp3 storage in GiB. | `number` | n/a | yes |
| client\_security\_group\_ids | Security groups admitted on 5432 (ECS tasks, DMS replication instance). | `list(string)` | n/a | yes |
| data\_subnet\_ids | Data subnets without an internet route, one per Availability Zone. | `list(string)` | n/a | yes |
| engine\_version | PostgreSQL major version. RDS picks the default minor and upgrades minors in the maintenance window. | `string` | n/a | yes |
| instance\_class | RDS instance class, sized in plan/target.yaml. | `string` | n/a | yes |
| kms\_key\_arn | KMS key for storage, Performance Insights and the managed master user secret. | `string` | n/a | yes |
| max\_allocated\_storage\_gb | Storage autoscaling ceiling in GiB. | `number` | n/a | yes |
| name | Name prefix for every resource in the module. | `string` | n/a | yes |
| vpc\_id | VPC that hosts the database. | `string` | n/a | yes |
| backup\_retention\_days | Automated backup retention in days. It replaces the nightly pg\_dump to the backup NAS (JOB-03). | `number` | `14` | no |
| deletion\_protection | Block deletion of the instance. Only a teardown of a test copy turns it off. | `bool` | `true` | no |
| multi\_az | Run a synchronous standby in a second Availability Zone. | `bool` | `true` | no |
| onprem\_client\_cidrs | On-premises hosts admitted on 5432 over the VPN, derived from the hybrid links in plan/waves.yaml. | `list(string)` | `[]` | no |
| skip\_final\_snapshot | Skip the final snapshot on destroy. Only the live test sets it, so its teardown leaves nothing behind. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| address | Host name of the RDS endpoint; the DMS target endpoint and the application connect to it. |
| instance\_identifier | RDS instance identifier, used in the runbook's CloudWatch checks. |
| master\_user\_secret\_arn | Secrets Manager secret that RDS manages for the master user. |
| onprem\_client\_cidrs | On-premises hosts admitted on 5432; tests compare it with the hybrid links in the plan. |
| port | PostgreSQL port. |
| publicly\_accessible | Whether RDS gives the instance a public address; always false. |
| security\_group\_id | Security group of the database. |
<!-- END_TF_DOCS -->
