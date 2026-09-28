# Live test

`make test-live` runs `scripts/test_live.sh`. It is manual, runs only in the sandbox account behind the `dev` profile,
and is not part of `make verify` or CI. It deploys the smallest slice of the wave 1 target that a mock cannot prove,
from the root in `infra/terraform/tests/live`: the VPC with its Site-to-Site VPN connection, and RDS for
PostgreSQL 16 with logical replication on. The script applies the slice from the plan it checked, asserts on it and
destroys it in the same run.

## Run

```bash
make test-live            # shows the caller identity and asks for confirmation
CONFIRM=yes make test-live
```

The script:

1. Shows the caller identity of the profile (`AWS_LIVE_PROFILE`, default `dev`) and asks for confirmation.
2. Runs the private-only pre-flight described below and stops if it fails.
3. Applies that exact plan file in `infra/terraform/tests/live`, asserts on the outputs (see Health checks) and
   destroys it. Everything carries the tags `purpose=portfolio-test` and `run=<run id>`, plus any tags given at run
   time in `TEST_LIVE_EXTRA_TAGS="Key1=value1,Key2=value2"` for an account whose tag policy or SCP requires them
   (never commit the values). The state lives in `build/live/state-<run id>.tfstate`; if the destroy fails (an
   expired SSO session, for example), the script keeps it and prints the command that retries the destroy.
4. Lists anything still tagged with the run ID after the destroy, and deletes the log groups RDS creates on its own.

Logs, the plan file, its JSON form and the state go to `build/live/`, which git ignores. A run costs under USD 1 and
takes about 25 minutes: a VPN connection and a `db.t4g.medium` instance. It creates no NAT gateway.

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

Before anything is created, `scripts/test_live.sh` runs `terraform plan -out` in the live root with the
run's variables, writes `terraform show -json` of that plan to `build/live/plan-<run id>.json` and runs
`python3 scripts/check_private_plan.py` on it. The script exits non-zero and lists every internet-facing resource it
finds: internet or egress-only gateways, public NAT gateways, Elastic IPs, default routes through a gateway, load
balancers without `internal = true`, security group ingress from `0.0.0.0/0` or `::/0`, ECS services with a public IP,
subnets that map public IPs, publicly accessible databases or DMS instances, Lambda function URLs, CloudFront, Global
Accelerator, API Gateway HTTP APIs and REST APIs that are not private. It also refuses any Route 53 resource (hosted
zones, records, health checks), a public EKS API endpoint and public S3 or ECR access: an ECR Public repository, an S3
website endpoint, a public bucket ACL, a public access block with any setting off, or a bucket or repository policy that
allows any principal without a condition. On any finding the live test stops before the apply.

### Offline tests

`make verify` runs three tests that fail if the live configuration turns public, with no AWS account:

- `tests/test_check_private_plan.py` (pytest) shows that the pre-flight passes a private plan and refuses each kind of
  internet-facing resource.
- `infra/terraform/tests/live_private` plans the live root with the mock provider and asserts that it creates no
  internet gateway, public NAT gateway, Elastic IP, default route or public-IP subnet, that the database is not
  publicly accessible and that no database ingress comes from `0.0.0.0/0` or `::/0`. Setting
  `internet_egress = true` in the live root makes it fail.
- `tests/test_live_scope.py` (pytest) walks the live root and every module it calls and fails if any of them declares
  an `aws_route53_*` resource. The weighted-record cutover (ADR 0003) stays in the offline plan, the `dns` module's
  mock-provider tests and the runbook; the live test never creates a hosted zone, record or health check.

### Health checks

The assertions in `scripts/test_live.sh` read what the AWS APIs return: the RDS endpoint and the VPN connection ID
from the Terraform outputs, and `PubliclyAccessible` from `rds describe-db-instances`. No check sends a request over
the internet to the deployed resources.
