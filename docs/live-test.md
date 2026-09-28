# Live test

`make test-live` runs `scripts/test_live.sh`. It is manual, runs only in the sandbox account behind the `dev` profile,
and is not part of `make verify` or CI. It deploys the smallest slice of the wave 1 target that a mock cannot prove,
from the root in `infra/terraform/tests/live`: the VPC with its Site-to-Site VPN connection, and RDS for
PostgreSQL 16 with logical replication on. `terraform test` applies the slice, checks it and destroys it in the same
run.

## Run

```bash
make test-live            # shows the caller identity and asks for confirmation
CONFIRM=yes make test-live
```

The script:

1. Shows the caller identity of the profile (`AWS_LIVE_PROFILE`, default `dev`) and asks for confirmation.
2. Runs the private-only pre-flight described below and stops if it fails.
3. Runs `terraform test` in `infra/terraform/tests/live`. Everything carries the tags `purpose=portfolio-test` and
   `run=<run id>`.
4. Lists anything still tagged with the run ID after the destroy, and deletes the log groups RDS creates on its own.

Logs, the plan file and its JSON form go to `build/live/`, which git ignores. A run costs under USD 1 and takes about
25 minutes: a VPN connection and a `db.t4g.medium` instance. It creates no NAT gateway.

## Private-only

The live test cannot create anything reachable from the internet ([ADR 0005](adr/0005-live-tests-run-private-only.md)).

- **Network.** The live root calls the network module with `internet_egress = false`. The VPC gets application and
  data subnets only: no internet gateway, public subnets, NAT gateways, Elastic IPs or default routes. The only route
  out of the VPC is the VPN route to the on-premises CIDR, learned from the virtual private gateway. The production
  root keeps the default (`true`) because wave 1 needs the NAT egress addresses the parcel carrier allowlists.
- **Load balancers and ECS.** The live root deploys no load balancer and no ECS service. A later change that adds
  them must set `internal = true` on the load balancer and `assign_public_ip = false` on the service; the pre-flight
  refuses anything else.
- **Security groups.** The database admits PostgreSQL only from `10.40.3.51/32`, an on-premises host behind the VPN.
  No rule admits `0.0.0.0/0` or `::/0`.
- **Database.** `publicly_accessible = false` and the instance sits in the data subnets.

### Pre-flight

Before `terraform test` creates anything, `scripts/test_live.sh` runs `terraform plan -out` in the live root with the
same variables the test uses, writes `terraform show -json` of that plan to `build/live/plan-<run id>.json` and runs
`python3 scripts/check_private_plan.py` on it. The script exits non-zero and lists every internet-facing resource it
finds: internet or egress-only gateways, public NAT gateways, Elastic IPs, default routes through a gateway, load
balancers without `internal = true`, security group ingress from `0.0.0.0/0` or `::/0`, ECS services with a public IP,
subnets that map public IPs, publicly accessible databases or DMS instances, Lambda function URLs, CloudFront,
Global Accelerator, API Gateway HTTP APIs and REST APIs that are not private. On any finding the live test stops
before the apply.

### Offline tests

`make verify` runs two tests that fail if the live configuration turns public, with no AWS account:

- `tests/test_check_private_plan.py` (pytest) shows that the pre-flight passes a private plan and refuses each kind of
  internet-facing resource.
- `infra/terraform/tests/live_private` plans the live root with the mock provider and asserts that it creates no
  internet gateway, public NAT gateway, Elastic IP, default route or public-IP subnet, that the database is not
  publicly accessible and that no database ingress comes from `0.0.0.0/0` or `::/0`. Setting
  `internet_egress = true` in the live root makes it fail.

### Health checks

The assertions in `infra/terraform/tests/live/live.tftest.hcl` read what the AWS APIs return to Terraform: the RDS
endpoint and the VPN connection ID. No check sends a request over the internet to the deployed resources.
