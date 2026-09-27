# Synthetic discovery data

Fictional discovery export for **Harbor Goods**, a fictional mid-size retailer. It covers the warehouse and inventory
application, which still runs on virtual machines in a colocation data center. The files mimic what agent-based
discovery and a DBA questionnaire return. No row describes a real system.

| File | Content | Typical real source |
| --- | --- | --- |
| `servers.csv` | 12 servers: role, software, size, 95th-percentile CPU and memory, private IP | Discovery agent export |
| `applications.csv` | 8 applications with owner, criticality, RTO, RPO and the longest write freeze the business accepts | Stakeholder interviews |
| `dependencies.csv` | Consumer to provider connections with port and purpose; `EXT-*` are parties outside the data center | Network connection data |
| `databases.csv` | One row per schema of the PostgreSQL database: size, largest LOB, tables without a primary key, change rate | DBA questionnaire and `pg_stat_*` views |
| `dns-records.csv` | Public and internal records with their current TTL | DNS zone export |
| `scheduled-jobs.csv` | Cron jobs, their schedule and what they write | `crontab -l` on each server |

Addresses use RFC 1918 space for the data center and `203.0.113.0/24` (a documentation range) for public
endpoints. Domains use `example.com`.

`scripts/check_plan.py` reads these files and fails if the plan in `plan/`, the Terraform or the runbook disagree
with them.
