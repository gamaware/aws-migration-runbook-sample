# 0006. Serve wave 1 from an internal load balancer, private DNS and private AWS API access

## Status

Accepted

## Context

The warehouse web app and the inventory API are internal: warehouse staff and handheld scanners use them from the
corporate network, and the storefront, already on AWS, calls the API from its own VPC. Nothing on the internet needs
them. The first target design still used an internet-facing Application Load Balancer, a security group rule that let
the ECS tasks and the DMS instance send HTTPS to `0.0.0.0/0` through NAT, and a workload-owned bucket for the ALB
access logs encrypted with SSE-S3. Trivy flagged all three (AWS-0053, AWS-0104, AWS-0132).

Constraints that shaped the options:

- The corporate network reaches AWS only through the Site-to-Site VPN (10.40.0.0/16), and the VPC is 10.60.0.0/16.
- The storefront VPC (10.50.0.0/16) is in the same account.
- The API calls one party outside AWS: the parcel carrier's label API, which allowlists the caller's address
  (prerequisite P-04) and publishes fixed addresses for its API.
- ALB access logging supports only SSE-S3 on the destination bucket (Elastic Load Balancing User Guide, "Enable
  access logs for your Application Load Balancer": "The only server-side encryption option that's supported is Amazon
  S3-managed keys (SSE-S3)"). Customer managed keys are supported for Network Load Balancer access logs, not for ALB.

## Decision

- **Internal load balancer.** The ALB sets `internal = true` and runs in the private application subnets. Its
  security group admits HTTP and HTTPS only from `alb_ingress_cidrs`, which the production root builds from
  `plan/target.yaml`: the corporate network (10.40.0.0/16, over the VPN), the storefront VPC (10.50.0.0/16, over a
  VPC peering connection) and the VPC itself (10.60.0.0/16, for the web tasks that call `api.example.com`). The
  variable has no default and rejects any range outside RFC 1918.
- **Private DNS.** The weighted pairs of ADR 0003 live in a Route 53 private hosted zone for `example.com`,
  associated with the wave 1 VPC and the storefront VPC. A Resolver inbound endpoint in the application subnets
  answers DNS on port 53 to the corporate network only; the corporate DNS servers forward the two wave 1 names to it
  (runbook step C-02), after which the old public records are deleted. The public zone keeps only the ACM DNS
  validation CNAMEs: they prove control of the names to the certificate authority and point at no endpoint, so the
  certificate for the internal listener still comes from ACM.
- **Private AWS API access.** The network module creates an S3 gateway endpoint and interface endpoints for
  `ecr.api`, `ecr.dkr`, `logs` and `secretsmanager`. Task HTTPS egress goes to the VPC CIDR (the interface endpoints
  and the internal ALB), to S3 through the gateway endpoint's prefix list, and to the carrier's published addresses
  (`carrier_api_cidrs`); the DMS instance sends HTTPS only to the VPC CIDR. No egress rule reaches `0.0.0.0/0`. The
  NAT gateways stay, because the carrier allowlists their Elastic IPs.
- **Access logs in the log archive.** Because an ALB cannot write to a bucket encrypted with a customer managed key,
  the workload no longer owns an access-log bucket. The ALB writes to the organization's central log archive bucket
  (`alb_access_logs` in `plan/target.yaml`), which the security team runs in the log archive account with the Elastic
  Load Balancing log-delivery policy, SSE-S3, retention and Object Lock. The workload's Terraform creates no S3
  bucket; the export bucket of step C-03 uses SSE-KMS.

## Consequences

- Staff reach the application only from the corporate network or its VPN; a warehouse that loses the VPN loses the
  application, as it would lose the data center today.
- Corporate DNS must forward the two names before T-48h. The runbook proves it at C-02, two days before the window,
  and rolls back with R-01 if it fails.
- The storefront team adds one route to 10.60.0.0/16 through the peering connection (prerequisite P-02).
- Interface endpoints add a small hourly charge per endpoint and Availability Zone. The live test sets
  `interface_endpoints = []` and keeps only the free S3 gateway endpoint.
- ALB access logs are encrypted with SSE-S3 in the log archive account, the only option ALB offers. The exception
  sits with the team that owns that bucket, not in this workload's code, and prerequisite P-12 checks that logs
  arrive there.
- Two scanner skips became obsolete and were removed: the WAF skip (Checkov CKV2_AWS_28 applies only to
  internet-facing load balancers) and the four skips on the former access-log bucket. RISK-07 (no AWS WAF yet) stays
  in the report as a hardening item for the internal load balancer.

## Compliance

The app module tests assert an internal load balancer in the subnets it is given, no ingress or egress to `0.0.0.0/0`
or `::/0`, HTTPS egress only to the VPC, the S3 prefix list and the carrier addresses, and access logs sent to the
log archive; they also show the variables rejecting public client ranges and wide carrier ranges. The dns module tests
assert that every weighted member lives in the private zone and that the Resolver endpoint admits only the corporate
network. The network and dms tests cover the endpoints and the DMS egress. The production test asserts the composed
values from `plan/target.yaml`. RUN-11 requires the public records to be deleted, not converted. Trivy runs in CI with
HIGH and CRITICAL findings failing the build and no inline ignores.

## Notes

If Elastic Load Balancing adds SSE-KMS support for ALB access logs, the log archive bucket can switch to its customer
managed key without any change here.
