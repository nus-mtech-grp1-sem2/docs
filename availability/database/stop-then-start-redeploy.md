# Stop-then-start redeploys for MySQL

Task 1 in [assesments.md](assesments.md). This report explains why the `onestage-mysql` ECS service is set to **minimum 0% / maximum 100%** running tasks with **Availability Zone rebalancing off**, what was changed, and what testing showed.

**Status (2026-10-07):** set by hand in the AWS console and tested. **Not yet in Terraform.** Until it is, the next `terraform apply` puts the old values back. See [Terraform](#terraform).

## The problem

MySQL runs as one ECS task. Its data directory (`/var/lib/mysql`) is on EFS, so the same files are visible to any MySQL task the service starts.

ECS's default deployment settings are minimum 100% / maximum 200%. For a service with one task, that means a redeploy:

1. starts a **new** MySQL task alongside the old one (2 tasks, which is 200%)
2. waits for the new task to pass its health check
3. only then stops the old task

So for a while, **two MySQL servers point at the same data directory.** MySQL isn't built for that. Its InnoDB storage engine expects to be the only process using its files. The likely outcomes are:

- **The new server can't lock the files and doesn't start.** It fails its health check, ECS keeps retrying, and the redeploy never finishes.
- **The file lock doesn't hold over EFS, and both servers write to the same files.** That corrupts the database, and you only find out later.

Neither is acceptable for the only copy of the data.

Every redeploy is exposed to this, and redeploys aren't rare. `ecs_mysql.tf` sets `force_new_deployment = true`, so **every `terraform apply` redeploys MySQL**.

## The fix

| Setting | Old | New | Why |
|---|---|---|---|
| Min running tasks % | 100 | **0** | Lets ECS stop the old task before the new one is up |
| Max running tasks % | 200 | **100** | Never more than one MySQL task, so ECS can't start a second one alongside the first |
| Availability Zone rebalancing | On | **Off** | Rebalancing moves a task by starting a new one before stopping the old one, so ECS requires max above 100% while it's on. With a single task there's nothing to rebalance anyway. |

With these settings, a redeploy **stops the old task first, waits until it's fully gone, then starts the new one.** At most one MySQL server ever uses the data directory.

**The cost is a short outage on every redeploy.** There's a gap with no database instead of a seamless handover. That's acceptable here: the seamless handover is exactly what's unsafe, and the alternative is risking corruption.

The other services (auth, order, ticket and so on) keep the defaults. They're stateless, so running two copies briefly is safe and avoids downtime.

## What was changed

2026-10-07, in the AWS console: **ECS** → `onestage-cluster` → `onestage-mysql` → **Update service** → **Deployment options**. AZ rebalancing was unticked, min was set to 0 and max to 100. **Force new deployment** was left unticked, so saving didn't restart MySQL.

Checked afterwards with `aws ecs describe-services`: `minimumHealthyPercent 0`, `maximumPercent 100`, `availabilityZoneRebalancing DISABLED`.

## Test

The MySQL task was stopped twice: once before the change and once after. The service, the MySQL logs and the settings were recorded both times.

| | Before (100% / 200%) | After (0% / 100%) |
|---|---|---|
| New task created, compared with the old task fully stopping | 62 s **before** | 9 s **after** |
| Old MySQL shutdown complete | 22:26:15 | 22:55:01 |
| New MySQL ready for connections | 22:27:15 | 22:57:09 |
| **Database unavailable** | **about 60 s** | **about 128 s** |
| InnoDB lock errors | none | none |
| Settings after the restart | n/a | still 0 / 100 / DISABLED |

What this shows:

- **ECS now waits for the old task to be completely gone before starting a new one.** Before the change, the new task was created while the old one was still shutting down. After the change, it was created 9 seconds after the old one had fully stopped.
- **The settings survive a restart.** Stopping and replacing a task doesn't reset them, and neither does the 02:00 / 18:00 scale schedule, which only changes the desired count.
- **The cost is about one extra minute of downtime.** ECS now waits for the old task's network and EFS mount to be released (about 1 minute) before starting the new one.

What it doesn't show:

- **In neither test did two MySQL servers actually run at the same time.** Stopping a task kills MySQL straight away (the logs show a clean shutdown within 15 s), and only the task cleanup lingers. The dangerous case is a **redeploy** under 100% / 200%, where ECS deliberately keeps the old server running until the new one is healthy. That wasn't reproduced on purpose, because doing so risks the production data. The reasoning in [The problem](#the-problem) follows from how ECS rolling deployments are documented to behave.
- **A forced redeploy under the new settings hasn't been run yet.** That's the path `terraform apply` takes. It should behave like the restart above, and it can be confirmed with `aws ecs update-service --force-new-deployment` in a quiet window.

Evidence is in [evidence/](evidence/):

- `stop-then-start-console-settings.png`: the console settings after the change
- [faster-detection-alert.md, Test results](faster-detection-alert.md#test-results-2026-10-07): the restart before the change (the alert test), and the restart after it, with service polling, task timestamps and MySQL log times for both

## Terraform

This change exists only in the console. `ecs_mysql.tf` doesn't set any of the three values, so the AWS provider falls back to its defaults (100 / 200, with rebalancing as the provider decides). **The next `terraform apply` will:**

1. put the old values back
2. redeploy MySQL (`force_new_deployment = true`) under those old values, in the same run

Step 2 is the unsafe overlap this change exists to prevent. **Until the code is updated, nobody should run `terraform apply` against this stack.**

The code change, in `backend-repo/infrastructure/terraform/ecs_mysql.tf`, inside `resource "aws_ecs_service" "mysql"`:

```hcl
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  availability_zone_rebalancing      = "DISABLED"
```

Once this is in, `terraform plan` should show no change for these fields, because the console already matches.

## Follow-ups

From [assesments.md](assesments.md), still open:

- **Deployment circuit breaker** (`deployment_circuit_breaker { enable = true, rollback = true }`). With min 0%, a failed redeploy could leave no MySQL running. The circuit breaker rolls back to the last working version instead.
- **Longer `stopTimeout`** (about 60–120 s, up from the default 30 s). In both tests MySQL shut down cleanly in about 3 s. A busy database may need longer, and if it's killed before it finishes, it has to run crash recovery on the next start.
