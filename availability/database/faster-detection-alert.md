# Faster detection: email when MySQL stops unexpectedly

Task 2 in [assesments.md](assesments.md). This guide sets up an email alert for when the MySQL ECS task stops for an unplanned reason. It is set up by hand in the AWS console, not in Terraform.

## Why not a CloudWatch alarm

The original plan was a CloudWatch alarm on the MySQL running task count. That doesn't work here, for two reasons:

- **The metric doesn't exist.** The running task count metric only exists when Container Insights is on, and `ecs_cluster.tf` turns it off to save cost.
- **It would go off every day.** The cluster is scaled to zero at 02:00 SGT every weekday (`scale_schedule.tf`), so a "fewer than 1 task" alarm would fire each morning.

Instead, an EventBridge rule watches the events ECS already sends when a task stops. These events are free and don't need Container Insights. The rule ignores planned stops and emails the team about everything else.

## What gets created

| Resource | Name | Purpose |
|---|---|---|
| SNS topic | `onestage-mysql-alerts` | The email list the alert goes to |
| SNS email subscriptions | one per recipient | Each recipient must confirm by email before they get alerts |
| EventBridge rule | `onestage-mysql-task-stopped` | Matches an unplanned stop of the MySQL task |

All three go in account `195663985359`, region **ap-southeast-1 (Singapore)**, on the `default` event bus.

**Terraform won't remove them.** Terraform only manages resources in its own code and state, so a later `terraform apply` leaves these alone. Because they aren't in code, this page is the only record that they exist.

**Cost:** effectively nothing. ECS events are free, and the SNS email volume is well within the free tier.

## Which stops alert

Every time an ECS task stops, ECS records a stop code. The rule decides on that code:

| Stop | Stop code | Alert? |
|---|---|---|
| Weekday 02:00 scale-to-zero | `ServiceSchedulerInitiated` | No |
| Normal redeploy | `ServiceSchedulerInitiated` | No |
| Container health check failed | `ServiceSchedulerInitiated`, with reason "Task failed container health checks" | **Yes** |
| MySQL process exited or crashed | `EssentialContainerExited` | **Yes** |
| Task failed to start | `TaskFailedToStart` | **Yes** |
| AWS retired the Fargate host | `TerminationNotice` | **Yes** |
| Someone ran `aws ecs stop-task` | `UserInitiated` | **Yes** (this is how the alert is tested) |

## Before you start

- Sign in to the AWS console as `SWE5001_permission_set_role` in account `195663985359`.
- Set the region (top right of the console) to **Asia Pacific (Singapore) ap-southeast-1**.
- Decide who gets the alert. The budget alert list in `backend-repo/infrastructure/terraform/terraform.tfvars` (`alert_emails`) is a sensible default.

## Step 1: Create the SNS topic

1. Open **Simple Notification Service (SNS)**, then **Topics**, then **Create topic**.
2. **Type:** Standard.
3. **Name:** `onestage-mysql-alerts`.
4. Leave **Encryption** off. EventBridge can't send to a topic encrypted with the AWS-managed SNS key. The alert only contains a task ID and a stop reason, so it doesn't need encryption.
5. Leave everything else as it is and click **Create topic**.
6. Copy the **topic ARN**. It looks like `arn:aws:sns:ap-southeast-1:195663985359:onestage-mysql-alerts`.

## Step 2: Add the email subscriptions

Repeat for each recipient:

1. On the topic page, click **Create subscription**.
2. **Protocol:** Email.
3. **Endpoint:** the recipient's email address.
4. Click **Create subscription**.

AWS then emails each recipient a link titled **AWS Notification - Subscription Confirmation**. Each person must click **Confirm subscription** in that email. Until they do, the subscription shows as **Pending confirmation** and they get nothing. If the email doesn't arrive, ask them to check their spam folder.

## Step 3: Create the EventBridge rule

1. Open **Amazon EventBridge**. The left menu has no **Rules** item any more, because rules now sit inside each event bus:
   - In the left menu, click **Event buses**.
   - Click the existing bus named **`default`**.
   - In its **Rules** section, click **Create rule**.

   **Don't create a new event bus.** If you land on **Create custom event bus**, cancel it. ECS only sends its events to the `default` bus, so a rule on any other bus never fires.

   The `default` bus already has a rule called `ecs-managed-capacity-provider-rule`, with **Type: Managed** and **Managed by: ecs.amazonaws.com**. ECS created it automatically to drain tasks off EC2 instances before they're terminated. It's unrelated to this alert, so leave it alone: don't edit, disable or delete it, or add a target to it. Create a new rule next to it.
2. **Define rule detail:**
   - **Name:** `onestage-mysql-task-stopped`
   - **Description:** `MySQL ECS task stopped for a reason other than a planned scale-down or deployment`
   - **Event bus:** `default`
   - **Rule type:** Rule with an event pattern
   - Click **Next**.
3. **Build event pattern:**
   - **Event source:** AWS events or EventBridge partner events.
   - **Creation method:** Custom pattern (JSON editor).
   - Paste this pattern:

   ```json
   {
     "source": ["aws.ecs"],
     "detail-type": ["ECS Task State Change"],
     "detail": {
       "clusterArn": ["arn:aws:ecs:ap-southeast-1:195663985359:cluster/onestage-cluster"],
       "group": ["service:onestage-mysql"],
       "lastStatus": ["STOPPED"],
       "$or": [
         { "stopCode": [{ "anything-but": ["ServiceSchedulerInitiated"] }] },
         { "stoppedReason": [{ "prefix": "Task failed container health checks" }] }
       ]
     }
   }
   ```

   - Click **Next**.
4. **Select target(s):**
   - **Target types:** AWS service.
   - **Select a target:** SNS topic.
   - **Topic:** `onestage-mysql-alerts`.
   - Open **Additional settings**. Under **Configure target input**, choose **Input transformer**, then click **Configure input transformer**.
   - **Target input transformer**, input path:

     ```json
     {
       "time": "$.time",
       "task": "$.detail.taskArn",
       "stopCode": "$.detail.stopCode",
       "reason": "$.detail.stoppedReason"
     }
     ```

   - **Template** (this is the email body):

     ```
     "MySQL task stopped unexpectedly at <time>. Stop code: <stopCode>. Reason: <reason>. Task: <task>. ECS will start a replacement; check the service's Events tab and that the API is serving again."
     ```

   - Click **Confirm**, then **Next**.
5. **Tags:** optional. To match the rest of the stack, add `Project = onestage` and `Course = swe5001`. Don't add `ManagedBy = terraform`, because this rule isn't managed by Terraform. Click **Next**.
6. Review the summary and click **Create rule**.

## Step 4: Let EventBridge send to the topic

The console does **not** add this permission when you pick the topic as the rule's target. A new topic's access policy only has the AWS default statement, so you have to add it yourself.

1. Open **SNS**, then **Topics**, then `onestage-mysql-alerts`, then **Edit**.
2. Expand **Access policy**.
3. Replace everything in the editor with the policy below, then click **Save changes**.

```json
{
  "Version": "2008-10-17",
  "Id": "__default_policy_ID",
  "Statement": [
    {
      "Sid": "__default_statement_ID",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "SNS:Publish",
        "SNS:RemovePermission",
        "SNS:SetTopicAttributes",
        "SNS:DeleteTopic",
        "SNS:ListSubscriptionsByTopic",
        "SNS:GetTopicAttributes",
        "SNS:AddPermission",
        "SNS:Subscribe"
      ],
      "Resource": "arn:aws:sns:ap-southeast-1:195663985359:onestage-mysql-alerts",
      "Condition": {
        "StringEquals": {
          "AWS:SourceAccount": "195663985359"
        }
      }
    },
    {
      "Sid": "AllowMySQLStopRule",
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:ap-southeast-1:195663985359:onestage-mysql-alerts",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "arn:aws:events:ap-southeast-1:195663985359:rule/onestage-mysql-task-stopped"
        }
      }
    }
  ]
}
```

- The first statement is the AWS default for a new topic, kept as it is. It lets people and services in this account manage and publish to the topic.
- The second statement, `AllowMySQLStopRule`, is the one being added. It lets EventBridge publish to the topic, but only from the `onestage-mysql-task-stopped` rule. If the rule has a different name, change the end of the `aws:SourceArn` line to match.

Without this permission the rule still matches, but no email is sent. The rule's **Monitoring** tab then shows `FailedInvocations`.

## Step 5: Test the pattern without stopping anything

This checks the rule's logic only. Nothing in the live system is touched.

1. Open **EventBridge**. In the left menu under **Developer resources**, click **Sandbox**, then the **Event pattern** tab.
2. **Sample event type:** Enter my own. Paste this event into the box. **Test pattern** stays greyed out until this box has an event in it.

   ```json
   {
     "version": "0",
     "id": "3317b2af-7005-947d-b652-f55e762e571a",
     "detail-type": "ECS Task State Change",
     "source": "aws.ecs",
     "account": "195663985359",
     "time": "2026-10-07T03:00:00Z",
     "region": "ap-southeast-1",
     "resources": ["arn:aws:ecs:ap-southeast-1:195663985359:task/onestage-cluster/0123456789abcdef0123456789abcdef"],
     "detail": {
       "clusterArn": "arn:aws:ecs:ap-southeast-1:195663985359:cluster/onestage-cluster",
       "group": "service:onestage-mysql",
       "lastStatus": "STOPPED",
       "desiredStatus": "STOPPED",
       "taskArn": "arn:aws:ecs:ap-southeast-1:195663985359:task/onestage-cluster/0123456789abcdef0123456789abcdef",
       "stopCode": "EssentialContainerExited",
       "stoppedReason": "Essential container in task exited"
     }
   }
   ```

   You can instead pick **AWS events** and choose `ECS Task State Change` from the **Sample events** dropdown, but then you have to edit `clusterArn`, `group` and `lastStatus` to match the pattern yourself.
3. Under **Event pattern**, choose **Custom pattern (JSON editor)** and paste the pattern from step 3.
4. Run three tests. For each one, set the `stopCode` and `stoppedReason` lines at the end of the **sample event** (the top box), click **Test pattern**, and screenshot the result. Don't change the event pattern.

   | Test | `stopCode` | `stoppedReason` | Expected |
   |---|---|---|---|
   | Crash | `EssentialContainerExited` | `Essential container in task exited` (as pasted) | **Matched** |
   | Planned scale-down or redeploy | `ServiceSchedulerInitiated` | `Scaling activity initiated by (deployment ecs-svc/123)` | **Did not match** |
   | Failed health check | `ServiceSchedulerInitiated` | `Task failed container health checks` | **Matched** |

   In the second test, the console shows a red **Sample event did not match the event pattern** banner. That is the correct result, not an error. It shows that the 02:00 scale-down stays quiet. The third test shows that a failed health check still alerts, even though ECS gives it the same stop code as a planned stop.

## Step 6: Test it for real

Do this during the [task 4](assesments.md) recovery-time test, in a quiet window, because it interrupts the live database:

```bash
aws ecs list-tasks --cluster onestage-cluster --service-name onestage-mysql \
  --region ap-southeast-1 --query "taskArns[0]" --output text

aws ecs stop-task --cluster onestage-cluster --task <task-arn-from-above> \
  --reason "Availability test: MySQL stop alert and RTO" --region ap-southeast-1
```

Within about a minute, every confirmed recipient should get an email with `Stop code: UserInitiated`.

Also check that the planned scale-down stays quiet: on the next weekday after 02:00 SGT, there should be **no** alert email.

## Test results (2026-10-07)

Step 6 was run on 2026-10-07 in region ap-southeast-1. **The alert fired, and MySQL came back by itself in about 2 minutes.**

### Checks before the stop

All read-only:

- Rule `onestage-mysql-task-stopped` is ENABLED on the `default` bus, with the pattern tested in step 5.
- Its target is the `onestage-mysql-alerts` topic, with the input transformer from step 3.
- The topic's access policy includes `AllowMySQLStopRule` for `events.amazonaws.com`.
- `onestagecontacts@gmail.com` is subscribed and confirmed.
- `onestage-mysql` had desired 1 and running 1.

### The stop

Issued at 22:25:57 SGT (14:25:57 UTC):

```
$ aws ecs stop-task --cluster onestage-cluster --task 1485b2d661d246b7a24350ce11f81851 \
    --reason "Availability test: MySQL stop alert and RTO" --region ap-southeast-1
{
    "taskArn": "arn:aws:ecs:ap-southeast-1:195663985359:task/onestage-cluster/1485b2d661d246b7a24350ce11f81851",
    "lastStatus": "DEACTIVATING",
    "desiredStatus": "STOPPED",
    "stoppedReason": "Availability test: MySQL stop alert and RTO"
}
```

### Timeline

| | Time (SGT) | Since stop |
|---|---|---|
| `stop-task` issued on task `1485b2d6…` | 22:25:57 | 0 s |
| Old MySQL shutdown complete (container log) | 22:26:15 | 18 s |
| ECS started replacement task `d8384433…` | 22:26:20 | 23 s |
| New MySQL ready for connections (container log) | 22:27:15 | 78 s |
| Old task reached STOPPED, so ECS sent the event the rule matches | 22:27:22 | 85 s |
| Alert email received | 22:27 | about 1.5 min |
| Replacement task RUNNING and HEALTHY | by 22:27:49 | about 112 s |
| Service reached steady state | 22:27:58 | 121 s |

The service, polled about every 13 s after the stop:

```
SGT                  elapsed  running  pending  task(lastStatus/health)
2026-10-07 22:26:29  31s      0        1        d8384433:PENDING/UNKNOWN
2026-10-07 22:26:42  44s      0        1        d8384433:PENDING/UNKNOWN
2026-10-07 22:26:55  57s      0        1        d8384433:PENDING/UNKNOWN
2026-10-07 22:27:09  71s      0        1        d8384433:ACTIVATING/UNKNOWN
2026-10-07 22:27:22  84s      0        1        d8384433:ACTIVATING/UNKNOWN
2026-10-07 22:27:36  98s      0        1        d8384433:ACTIVATING/UNKNOWN
2026-10-07 22:27:49  111s     0        1        d8384433:RUNNING/HEALTHY
```

The ECS service events:

```
2026-10-07T22:27:57  (service onestage-mysql) has reached a steady state.
2026-10-07T22:26:20  (service onestage-mysql) has started 1 tasks: (task d838443363984127b3a47cafaca0e0ed).
2026-10-07T18:01:49  (service onestage-mysql) has reached a steady state.
2026-10-07T18:00:15  (service onestage-mysql) has started 1 tasks: (task 1485b2d661d246b7a24350ce11f81851).
2026-10-07T02:00:07  (service onestage-mysql) has stopped 1 running tasks: (task 522f73f7ab894b2fb15ccd82b1692090).
```

### What it shows

- **The alert works end to end.** The rule matched 1 event and sent it to SNS once, with 0 failures. SNS recorded 1 message published, 1 delivered and 0 failed (`step6-cloudwatch-sns-metrics.png`; graph times are UTC, so 14:27 is 22:27 SGT). The email arrived with `Stop code: UserInitiated`, the test reason, and the stopped task's ARN (`step6-gmail-alert-email.png`).
- **Where the delay comes from:** nearly all of the 1.5 minutes before the email is the old task shutting down. ECS only sends the event once the task reaches STOPPED, which took 85 s here, and the email followed within seconds. A sudden crash stops the task immediately, so its email should arrive sooner.
- **Recovery time:** about 112 s from the stop to a healthy database, with no manual action. The status was only polled about every 13 s, so the true time could be up to that much shorter. This doesn't include the time for the API services to reconnect.
- **Blast radius:** only `onestage-mysql` went to 0/1. The other eight services stayed at 1/1 the whole time (`step6-ecs-mysql-stopped-0of1.png`, `step6-ecs-mysql-replacement-starting.png`, `step6-ecs-mysql-recovered-1of1.png`).

### Restart after the stop-then-start change

Later the same evening, the MySQL service was changed to stop-then-start redeploys (minimum 0%, maximum 100%, AZ rebalancing off; see [stop-then-start-redeploy.md](stop-then-start-redeploy.md)). The task was then stopped again from the console to compare. This stop also sent an alert (`UserInitiated`).

```
SGT                  running  pending  tasks(id:lastStatus/health)
2026-10-07 22:56:26  0        1        dd03d2d4:PENDING/UNKNOWN d8384433:STOPPED/UNKNOWN
2026-10-07 22:56:40  0        1        dd03d2d4:PENDING/UNKNOWN d8384433:STOPPED/UNKNOWN
2026-10-07 22:56:55  0        1        dd03d2d4:PENDING/UNKNOWN d8384433:STOPPED/UNKNOWN
2026-10-07 22:57:10  0        1        dd03d2d4:ACTIVATING/UNKNOWN d8384433:STOPPED/UNKNOWN
2026-10-07 22:57:25  0        1        dd03d2d4:RUNNING/HEALTHY d8384433:STOPPED/UNKNOWN
```

| | Before the change (22:26) | After the change (22:55) |
|---|---|---|
| Settings | min 100%, max 200% | min 0%, max 100%, AZ rebalancing off |
| Old MySQL shutdown complete | 22:26:15 | 22:55:01 |
| Old task fully STOPPED | 22:27:22 | 22:56:08 |
| New task created | 22:26:20, **62 s before** the old task stopped | 22:56:17, **9 s after** |
| New MySQL ready for connections | 22:27:15 | 22:57:09 |
| Replacement task RUNNING and HEALTHY | by 22:27:49 | by 22:57:25 |
| **Database unavailable** | **about 60 s** | **about 128 s** |
| InnoDB lock errors in the logs | none | none |

- **ECS now waits for the old task to be fully gone** (network and EFS mount released) before it starts the new one.
- **In neither test did two MySQL servers run at the same time.** Before the change the two ECS tasks overlapped, but a stop kills the old MySQL straight away (shutdown complete within about 18 s), so only the task cleanup overlapped. The real risk is a redeploy; see [stop-then-start-redeploy.md](stop-then-start-redeploy.md).
- **The cost is about one extra minute of downtime per restart.**
- **The settings survived the restart.** After it, the service was still at min 0%, max 100%, AZ rebalancing DISABLED, desired 1, running 1.

## Check the setup from the CLI

These commands only read:

```bash
aws events describe-rule --name onestage-mysql-task-stopped --region ap-southeast-1
aws events list-targets-by-rule --rule onestage-mysql-task-stopped --region ap-southeast-1
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:ap-southeast-1:195663985359:onestage-mysql-alerts --region ap-southeast-1
```

In the subscriptions output, a confirmed subscriber has a real subscription ARN. An unconfirmed one shows `PendingConfirmation`.

## Evidence to keep

Save these in `availability/database/evidence/`:

- [ ] Screenshot of the SNS topic and its subscriptions, all showing **Confirmed** (subscription was confirmed on 2026-10-07; screenshot not kept)
- [ ] Screenshot of the EventBridge rule: its event pattern and target
- [ ] Screenshots of the step 5 sandbox tests: two matches, one non-match (tests passed on 2026-10-07; screenshots not kept)
- [x] The step 6 `stop-task` command and its output: see [Test results](#test-results-2026-10-07), plus `step6-ecs-mysql-stopped-0of1.png` and `step6-ecs-mysql-replacement-starting.png`
- [x] The alert email received after the stop (`step6-gmail-alert-email.png`)
- [ ] Note that no email arrived after the next 02:00 scale-down

## Removing it

1. Open **EventBridge**, then **Event buses**, then `default`. In its **Rules** section, select `onestage-mysql-task-stopped` and click **Delete**.
2. Open **SNS**, then **Topics**, then `onestage-mysql-alerts`, then **Delete**. This also removes its subscriptions.

## Adding or removing a recipient

- **Add:** follow step 2 for the new address. They must confirm the email.
- **Remove:** open **SNS**, then **Subscriptions**, select the subscription and click **Delete**. Recipients can also unsubscribe with the link at the bottom of any alert email.
