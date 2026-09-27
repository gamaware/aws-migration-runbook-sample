# Module: dms

AWS DMS replication instance, four endpoints and two tasks: a full load plus change data capture from the data
center to RDS, and a change-data-capture-only task back to the data center for rollback. Credentials live in
Secrets Manager and neither task starts on apply. Tests: `tests/dms.tftest.hcl`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0 |
| aws | >= 6.0, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 6.0, < 7.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_dms_endpoint.onprem_source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_endpoint) | resource |
| [aws_dms_endpoint.onprem_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_endpoint) | resource |
| [aws_dms_endpoint.rds_source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_endpoint) | resource |
| [aws_dms_endpoint.rds_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_endpoint) | resource |
| [aws_dms_replication_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_instance) | resource |
| [aws_dms_replication_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_subnet_group) | resource |
| [aws_dms_replication_task.forward](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_task) | resource |
| [aws_dms_replication_task.reverse](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_task) | resource |
| [aws_iam_role.dms_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.dms_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.secrets_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.secrets_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.dms_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.dms_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_secretsmanager_secret.onprem](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.rds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_security_group.dms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.to_aws_apis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.to_onprem_postgres](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.to_rds_postgres](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| forward\_task | Data center to RDS task, from plan/data-migration.yaml. | ```object({ id = string migration_type = string table_mappings = string settings = string })``` | n/a | yes |
| kms\_key\_arn | KMS key for the replication instance storage, the endpoints and the credential secrets. | `string` | n/a | yes |
| name | Name prefix for every resource in the module. | `string` | n/a | yes |
| onprem\_cidr | CIDR block of the data center; the replication instance reaches the source database inside it. | `string` | n/a | yes |
| onprem\_database | Source database in the data center (SRV-07). | ```object({ server_name = string port = number database_name = string })``` | n/a | yes |
| rds\_database | Target database on RDS. | ```object({ server_name = string port = number database_name = string })``` | n/a | yes |
| reverse\_task | RDS to data center task, from plan/data-migration.yaml. It only runs after cutover. | ```object({ id = string migration_type = string table_mappings = string settings = string })``` | n/a | yes |
| subnet\_ids | Application subnets: they route to the data center over the VPN and to Secrets Manager through NAT. | `list(string)` | n/a | yes |
| vpc\_cidr | CIDR block of the VPC; the replication instance reaches RDS inside it. | `string` | n/a | yes |
| vpc\_id | VPC that hosts the replication instance. | `string` | n/a | yes |
| allocated\_storage\_gb | Replication instance storage for cached changes and task logs. | `number` | `200` | no |
| create\_service\_roles | Create dms-vpc-role and dms-cloudwatch-logs-role. Set false if the account already has them. | `bool` | `true` | no |
| instance\_class | Replication instance class. | `string` | `"dms.r6i.large"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| credential\_secrets | Secrets the DBA fills before the full load: host, port, username and password as JSON keys. |
| forward\_task\_id | Identifier of the full load and CDC task; the runbook starts and monitors it by this name. |
| replication\_instance\_arn | ARN of the replication instance. |
| reverse\_task\_id | Identifier of the reverse CDC task that keeps the data center current after cutover. |
| security\_group\_id | Security group of the replication instance; the database admits it on 5432. |
<!-- END_TF_DOCS -->
