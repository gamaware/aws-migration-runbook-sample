# Smoke tests for the wave 1 cutover

Run at C-17, before the DNS switch, against the load balancer from a corporate workstation: the load balancer is
internal, so it answers only over the VPN. `curl --resolve` sends each request to it while keeping the real host
name, so TLS and host routing are tested as users will see them:

```bash
ALB_IP="$(dig +short "$(terraform output -raw alb_dns_name)" | head -1)"
curl -sS --resolve "warehouse.example.com:443:$ALB_IP" https://warehouse.example.com/healthz
```

The service account `smoke-test` exists in production, is excluded from reporting, and its credentials live in Secrets
Manager. Its test orders carry a test flag, so they are never released to the warehouse floor. Go/no-go criterion G-07
requires every test to pass.

| ID | Host | Test | Pass condition |
| --- | --- | --- | --- |
| S-01 | warehouse.example.com | `GET /healthz` | HTTP 200 |
| S-02 | warehouse.example.com | `GET /` | HTTP 200 and the page title contains "Harbor Goods" |
| S-03 | warehouse.example.com | `GET /locations?zone=A` | HTTP 200 and at least 20 bin locations |
| S-04 | warehouse.example.com | `http://` request on port 80 | HTTP 301 to the same path over HTTPS |
| S-05 | api.example.com | `GET /actuator/health` | HTTP 200 and `"status":"UP"` |
| S-06 | api.example.com | `GET /v1/stock/HG-10001` | HTTP 200 and the on-hand quantity equals the value on SRV-07 |
| S-07 | api.example.com | Sign in as the `smoke-test` service account | HTTP 200 and a session token |
| S-08 | api.example.com | `GET /v1/orders?client=smoke-test` | HTTP 200 and the same order count as on SRV-07 |
| S-09 | api.example.com | Create a test fulfillment order for one unit of `HG-10001` | HTTP 201 and a new order ID above the V-04 maximum |
| S-10 | api.example.com | Reach the parcel carrier's status endpoint from a task, through the NAT addresses | HTTP 200, proving the allowlist from P-04 is in place |
| S-11 | api.example.com | Cancel the test order | HTTP 200 and status "cancelled" |
| S-12 | both | TLS certificate | Issued by Amazon, valid for both names, not expiring within 30 days |
