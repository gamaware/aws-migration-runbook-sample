# Smoke tests for the wave 1 cutover

Run at C-17, before the DNS switch, against the load balancer. `curl --resolve` sends each request to the
load balancer while keeping the real host name, so TLS and host routing are tested as customers will see them:

```bash
ALB_IP="$(dig +short "$(terraform output -raw alb_dns_name)" | head -1)"
curl -sS --resolve "shop.example.com:443:$ALB_IP" https://shop.example.com/healthz
```

The test customer `smoke-test@example.com` exists in production, is excluded from reporting, and its credentials live in
Secrets Manager. Go/no-go criterion
G-07 requires every test to pass.

| ID | Host | Test | Pass condition |
| --- | --- | --- | --- |
| S-01 | shop.example.com | `GET /healthz` | HTTP 200 |
| S-02 | shop.example.com | `GET /` | HTTP 200 and the page title contains "Harbor Goods" |
| S-03 | shop.example.com | `GET /catalog/bestsellers` | HTTP 200 and at least 20 products |
| S-04 | shop.example.com | `http://` request on port 80 | HTTP 301 to the same path over HTTPS |
| S-05 | api.example.com | `GET /actuator/health` | HTTP 200 and `"status":"UP"` |
| S-06 | api.example.com | `GET /v1/products/HG-10001` | HTTP 200 and the price equals the value on SRV-07 |
| S-07 | api.example.com | Sign in as the test customer | HTTP 200 and a session token |
| S-08 | api.example.com | `GET /v1/customers/me/orders` for the test customer | HTTP 200 and the same order count as on SRV-07 |
| S-09 | api.example.com | Place a test order paid with the test customer's store credit (no card is charged) | HTTP 201 and a new order ID above the V-04 maximum |
| S-10 | api.example.com | Reach the payment provider's status endpoint from a task, through the NAT addresses | HTTP 200, proving the allowlist from P-04 is in place |
| S-11 | api.example.com | Cancel the test order | HTTP 200 and status "cancelled" |
| S-12 | both | TLS certificate | Issued by Amazon, valid for both names, not expiring within 30 days |
