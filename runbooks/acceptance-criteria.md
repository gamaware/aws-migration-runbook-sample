# Post-migration acceptance criteria: wave 1

Wave 1 is accepted when every criterion below is met during the seven days of hypercare. CL checks them at C-23;
BIZ signs. Baselines come from the discovery period on the data center.

| ID | Area | Criterion | Threshold | Measured by | When |
| --- | --- | --- | --- | --- | --- |
| A-01 | Availability | Synthetic checks on `warehouse.example.com` and `api.example.com` succeed | >= 99.9 percent of checks over 7 days | CloudWatch Synthetics canary every 5 min | Hypercare |
| A-02 | Latency | Inventory API p95 target response time | <= 350 ms (baseline 310 ms on premises) | ALB `TargetResponseTime` p95, daily | Hypercare |
| A-03 | Errors | Share of requests answered with 5xx | < 0.5 percent per day | ALB `HTTPCode_Target_5XX_Count` over `RequestCount` | Hypercare |
| A-04 | Data | Rows and checksums at cutover, and fulfillment orders lost or duplicated since | = 0 differences in V-02 to V-04; = 0 confirmed cases | Validation log and support tickets | C-15 and hypercare |
| A-05 | Downtime | Actual write freeze from C-10 to C-19 | <= 30 min | Bridge log | Cutover night |
| A-06 | Shipping labels | Carrier label request success rate | >= 98 percent per day (baseline 98.6 percent) | Carrier API dashboard | Hypercare |
| A-07 | Recovery | Point-in-time restore of RDS to a scratch instance | <= 60 min to a usable instance, then deleted | Restore drill log | Day 3 of hypercare |
| A-08 | Batch | JOB-01 and JOB-02 finish over the hybrid link | = 3 of 3 nights; row-count difference <= 1 percent of baseline | Job logs on SRV-09 | Hypercare |
| A-09 | Security | Database exposure and scanner results | = 0 public endpoints on RDS; = 0 failed Checkov checks | `make verify`, AWS Config rule `rds-instance-public-access-check` | C-23 |
| A-10 | Operations | Handover to the Harbor Goods on-call team | = 100 percent of runbook, dashboards and alarms walked through and acknowledged | Handover checklist | C-23 |
