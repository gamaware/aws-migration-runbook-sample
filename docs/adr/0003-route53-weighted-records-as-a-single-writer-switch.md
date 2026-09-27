# ADR 0003: Use Route 53 weighted records as a switch, never as a traffic split

## Status

Accepted

## Context

Customers reach `shop.example.com` and `api.example.com`, both served by the data center today with a one-hour TTL.
The database has one writer. Sending some customers to AWS and others to the data center at the same time would
split writes across two databases.

## Decision

Each name becomes a weighted pair at T-48h: an `onprem` member pointing at the data center address and an `aws`
member aliasing the load balancer. Weights are 100/0 or 0/100, nothing in between; the DNS module rejects any other
combination. The alias does not evaluate target health, because with a 0/100 pair Route 53 would otherwise fail over
to the zero-weight data center member on its own. The TTL drops to 60 seconds at T-72h, more than twice the old
TTL before the switch.

## Consequences

- The switch (C-19) and the rollback change weights only; resolvers follow within about a minute.
- No canary: the first customer request on AWS is a real one. Smoke tests through `curl --resolve` (C-17) stand in
  for it.
- Terraform updates the members one call at a time; the break-glass change batch flips all four in one call.

## Compliance

The DNS module's variable validation rejects split weights, and its tests assert 100/0 before and 0/100 after. RUN-11
checks the TTL lead time and the change batches against the inventory.

## Notes

A weighted pair also makes the rollback a one-line change, which a CNAME swap at the registrar would not.
