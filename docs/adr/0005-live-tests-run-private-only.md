# 0005. Live tests run private-only

## Status

Accepted

## Context

`make test-live` deploys a slice of the wave 1 target to a sandbox account to prove what a mock cannot: that AWS
accepts the VPN tunnel options and creates PostgreSQL 16 with logical replication on. The network module it uses
builds the production layout, which includes an internet gateway, public subnets, one NAT gateway and Elastic IP per
Availability Zone, and default routes. The live test needs none of these, and each one is a resource reachable from,
or routing to, the internet in a sandbox account.

## Decision

Live tests create nothing internet-facing. The network module gains `internet_egress` (default `true`); the live root
sets it to `false`, which removes the internet gateway, public subnets, NAT gateways, Elastic IPs and default routes.
The VPC keeps its application and data subnets, and its only way out is the VPN route to the on-premises CIDR. The
production root keeps the default, because wave 1 needs the NAT egress addresses that the parcel carrier allowlists
(prerequisite P-04).

Before any apply, `scripts/test_live.sh` plans the live root with the exact test variables, converts the plan with
`terraform show -json` and runs `scripts/check_private_plan.py` on it. The run stops on any internet-facing resource:
a gateway, Elastic IP or default route to the internet, a load balancer that is not internal, security group ingress
from `0.0.0.0/0` or `::/0`, an ECS task with a public IP, a subnet that maps public IPs or a publicly accessible
database. The live assertions read the results of AWS API calls through Terraform; no health check crosses the
internet.

## Consequences

- A live run cannot expose the sandbox account, even when a later change adds resources to the live root.
- The live test no longer exercises the NAT egress path. The mocked network tests still cover it, and the parcel carrier
  confirms the allowlisting during the rehearsal.
- A run creates fewer billed resources, and fewer to clean up after an interrupted run.
- The network module has two modes to keep tested.

## Compliance

`make verify` runs `tests/test_check_private_plan.py`, which shows the pre-flight refusing each kind of internet-facing
resource, and `infra/terraform/tests/live_private`, which plans the live root with the mock provider and fails if it
would create an internet gateway, public NAT gateway, Elastic IP, default route, public-IP subnet, a publicly
accessible database or database ingress from `0.0.0.0/0` or `::/0`. The network module test
`private_only_mode_has_no_internet_path` checks the module's private mode on its own. See
[`docs/live-test.md`](../live-test.md).

## Notes

Alternatives considered: a separate live-only network module, which would drift from the production module the test
has to prove, and relying on the pre-flight alone, which catches a public plan only at run time instead of in
every `make verify`.
