# Module: network

Target VPC for Harbor Goods: public, application and data subnets in two Availability Zones, one NAT gateway
per zone (only for the parcel carrier's allowlisted API), a Site-to-Site VPN to the data center with IKEv2 tunnels,
VPC endpoints (an S3 gateway endpoint and interface endpoints for ECR, CloudWatch Logs and Secrets Manager), an
optional peering connection to the storefront VPC, and VPC flow logs encrypted with KMS. The data subnets have no
internet route; they reach the data center only through routes propagated from the VPN gateway. Tests:
`tests/network.tftest.hcl`.

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
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_customer_gateway.onprem](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/customer_gateway) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.app_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.app_to_storefront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_subnet.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_peering_connection.storefront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection) | resource |
| [aws_vpc_security_group_ingress_rule.endpoints_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpn_connection.onprem](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection) | resource |
| [aws_vpn_connection_route.onprem](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection_route) | resource |
| [aws_vpn_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway) | resource |
| [aws_vpn_gateway_route_propagation.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway_route_propagation) | resource |
| [aws_vpn_gateway_route_propagation.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_gateway_route_propagation) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| azs | Availability Zones to spread the public, application and data subnets across. | `list(string)` | n/a | yes |
| kms\_key\_arn | KMS key that encrypts the VPC flow log group. | `string` | n/a | yes |
| name | Name prefix for every resource in the module. | `string` | n/a | yes |
| onprem\_cidr | CIDR block of the on-premises data center reached through the Site-to-Site VPN. | `string` | n/a | yes |
| vpc\_cidr | CIDR block of the target VPC. | `string` | n/a | yes |
| vpn\_peer\_ip | Public IP of the on-premises VPN device (customer gateway). | `string` | n/a | yes |
| flow\_log\_retention\_days | Retention of the VPC flow log group in days. | `number` | `365` | no |
| interface\_endpoints | AWS services that get an interface VPC endpoint in the application subnets (the service name suffix, such as ecr.api). | `list(string)` | ```[ "ecr.api", "ecr.dkr", "logs", "secretsmanager" ]``` | no |
| internet\_egress | Create the internet gateway, public subnets, NAT gateways and default routes. The live test sets false. | `bool` | `true` | no |
| storefront\_vpc | Storefront VPC in the same account to peer with, so it reaches the internal load balancer. Null creates no peering. | ```object({ id = string cidr = string })``` | `null` | no |
| vpn\_bgp\_asn | BGP ASN of the customer gateway. The tunnels use static routes; AWS still requires an ASN. | `number` | `65000` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| app\_subnet\_ids | Application subnets, one per Availability Zone (internal load balancer, ECS tasks, interface endpoints and the DMS replication instance). |
| data\_subnet\_ids | Data subnets without an internet route, one per Availability Zone (RDS). |
| interface\_endpoint\_services | Services reached through interface VPC endpoints instead of the internet. |
| internet\_exposure | Counts of resources that make the VPC reachable from, or route to, the internet; all zero when internet\_egress is false. |
| nat\_public\_ips | Egress addresses the parcel carrier must allowlist before cutover. |
| public\_subnet\_ids | Public subnets, one per Availability Zone (NAT gateways only; the load balancer is internal). |
| s3\_prefix\_list\_id | Prefix list of the S3 gateway endpoint, for security group egress to S3. |
| storefront\_peering\_connection\_id | VPC peering connection to the storefront VPC, or null when there is none. |
| vpc\_cidr | CIDR block of the target VPC. |
| vpc\_id | ID of the target VPC. |
| vpn\_connection\_id | ID of the Site-to-Site VPN connection to the data center. |
<!-- END_TF_DOCS -->
