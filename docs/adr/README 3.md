# Architecture decision records

Architecture decision records follow the *Fundamentals of Software Architecture* (2nd ed.) format.

| Number | Title | Status |
| --- | --- | --- |
| [0001](0001-replatform-to-ecs-fargate-and-rds.md) | Replatform the warehouse application tier to ECS Fargate and Amazon RDS | Accepted |
| [0002](0002-dms-full-load-cdc-with-reverse-replication.md) | Move the data with AWS DMS full load plus CDC, and keep a reverse task for rollback | Accepted |
| [0003](0003-route53-weighted-records-as-a-single-writer-switch.md) | Use Route 53 weighted records as a switch, never as a traffic split | Accepted |
| [0004](0004-plan-files-as-the-single-source-of-truth.md) | Keep the plan in data files that Terraform, the checks and the runbook share | Accepted |
