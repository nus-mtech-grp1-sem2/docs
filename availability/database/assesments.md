# Database availability notes

## Options

1. **Harden the current single task.** Keep MySQL on one ECS task and make it more robust.
2. **Switch to RDS Multi-AZ.** The production-grade option.

## Comparison

| | Harden single task | RDS Multi-AZ |
|---|---|---|
| Removes the single point of failure | No | Yes, failover in about 1–2 minutes |
| Cost | Near zero | Roughly $40–50 a month for the smallest instance, running continuously (estimate, not checked against current pricing) |
| Risk to the project | Very low | Data migration plus Terraform, secrets and network changes, a few weeks before the demo |
| Fits the scale-to-zero schedule | Yes | Partly; RDS can be stopped, but only for 7 days at a time |

## Decision

Based on cost and timing, we harden the single task.

## Tasks

1. **Stop-then-start redeploys.** Set the MySQL service to minimum 0% / maximum 100% healthy, so two tasks never open the data directory at the same time.
2. **Faster detection.** Send an alert when the MySQL task stops unexpectedly (see Open Tasks for why the original CloudWatch alarm on running task count won't work).
3. **Smaller data-loss window.** Move the EFS backup from daily to hourly, cutting RPO from about 24 hours to about 1 hour.
4. **Measured recovery time.** Kill the MySQL task once and time how long until the system serves requests again. That number is the RTO.
5. **Proven restore.** Restore one backup into a scratch EFS once, so the backup is known to work.

## Complete Tasks

None yet.

## Open Tasks
1. **Stop-then-start redeploys.** Set in the console and tested on 2026-10-07: minimum 0%, maximum 100%, AZ rebalancing off. Not yet in Terraform, so the next `terraform apply` reverts it. Report: [stop-then-start-redeploy.md](stop-then-start-redeploy.md).
   - Add `deployment_minimum_healthy_percent = 0` and `deployment_maximum_percent = 100` to the MySQL service in Terraform, not the console. A console-only change would likely be reverted by the next `terraform apply`.
   - Add `deployment_circuit_breaker { enable = true, rollback = true }`, so a failed deploy rolls back instead of leaving no MySQL task running.
   - Raise the container `stopTimeout` to about 60–120s (the default is 30s), so MySQL shuts down cleanly instead of being killed and running crash recovery on the next start.
   - Trade-off: every redeploy becomes a short outage (about 1–3 minutes, not yet measured) while the old task stops and the new one starts.
2. **Faster detection.** Not done, and the original plan won't work. The running task count metric needs Container Insights, which `ecs_cluster.tf` turns off. The weekday scale-to-zero would also set off a "fewer than 1 task" alarm every day.
   - Option A (chosen): an EventBridge rule that emails when the MySQL task stops unexpectedly, filtering out the planned scale-downs. Set up by hand in the AWS console, not in Terraform. Step-by-step guide: [faster-detection-alert.md](faster-detection-alert.md).
   - Option B (not chosen): turn on Container Insights (extra cost) and alarm only while the service is meant to be running.
3. **Smaller data-loss window.** Move the EFS backup from daily to hourly, cutting RPO from about 24 hours to about 1 hour.
4. **Measured recovery time.** Not done. Kill the MySQL task once and time how long until the system serves requests again. That number is the RTO.
5. **Proven restore.** Restore one backup into a scratch EFS once, so the backup is known to work.



## Open question

The kill test in step 4 also answers something not yet verified: whether the services reconnect on their own after MySQL comes back. If they do not, recovery needs manual restarts, and that would be the most valuable thing to fix.

