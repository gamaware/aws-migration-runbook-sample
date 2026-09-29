# 0003. Use Route 53 weighted records as a switch, never as a traffic split

## Status

Accepted

## Context

Warehouse staff on the corporate network and the storefront on AWS reach `warehouse.example.com` and
`api.example.com`, both served by the data center today through public records with a one-hour TTL. The database has
one writer. Sending some users to AWS and others to the data center at the same time would split writes across two
databases. The target load balancer is internal (ADR 0006), so the names must resolve privately.

## Decision

Each name is a weighted pair at the apex of its own Route 53 private hosted zone that Terraform creates with the target:
an `onprem` member pointing at the data center address and an `aws` member aliasing the internal load balancer. The
zones are associated with the wave 1 VPC and the storefront VPC, and the corporate DNS servers forward both names to a
Resolver inbound endpoint over the VPN. At T-48h (C-02) the forwarders go live and the public records are deleted, so
from then on every client resolves the pair. Weights are 100/0 or 0/100, nothing in between; the DNS module rejects any
other combination. The alias does not evaluate target health, because with a 0/100 pair Route 53 would otherwise fail
over to the zero-weight data center member on its own. The public TTL drops to 60 seconds at T-72h, more than twice the
old TTL before the switch, so no resolver keeps the public answer long after C-02 deletes it.

## Consequences

- The switch (C-19) and the rollback change weights only; resolvers follow within about a minute.
- No canary: the first user request on AWS is a real one. Smoke tests through `curl --resolve` (C-17) stand in
  for it.
- Terraform updates the members one call at a time; the break-glass path sends one change batch per zone, each
  flipping both members of its name. It targets the private zones by the IDs recorded in P-03, because a lookup by
  name could find a public zone. Both sides are frozen or in maintenance while the batches land, so the seconds
  between them split no writes.
- The weights live in `production.tfvars`, so a later apply cannot move users back by accident.
- The switch depends on the corporate forwarders and the storefront zone association, both proven at C-02.

## Compliance

The DNS module's variable validation rejects split weights, and its tests assert 100/0 before and 0/100 after and that
every member lives at the apex of its own private zone. RUN-11 checks the TTL lead time, the public-record deletion
batch and the break-glass batches against the inventory.

## Notes

A weighted pair also makes the rollback a one-line change, which a CNAME swap at the registrar would not.
