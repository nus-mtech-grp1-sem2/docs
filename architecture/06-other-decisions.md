# Other Architectural Decisions

These decisions shape how OneStage is built, delivered, secured and paid for, but belong to neither the logical nor the physical view. Several are explained further in the DevOps and Quality Attributes chapters of the report.

Table: Other architectural decisions

| Identifier | Description |
|---|---|
| AD-23 | Define all AWS infrastructure in Terraform with one state file in a versioned, encrypted S3 bucket using native lock files, and apply it manually after review. CI only formats, validates and scans Terraform. Trade-off: no accidental applies from CI against no GitOps, and console changes can drift from the code |
| AD-24 | Let GitHub Actions deploy through IAM roles assumed with GitHub's OIDC tokens, trusted only for the `main` branch of each repository. Trade-off: no long-lived AWS keys anywhere against more complex trust policies |
| AD-25 | Deploy the backend only after lint, build and unit tests pass, by rolling out a new image to every ECS service (`force-new-deployment`). Trade-off: simple and gated against `:latest` tags, no automatic rollback and no canary (AISS-06) |
| AD-26 | Scan every change for security issues: dependency audit (`audit-ci`, high and critical fail the build), Semgrep SAST, tfsec and TFLint on Terraform, and a weekly OWASP ZAP baseline DAST. Advisories with no fix are allowlisted per path with an owner and an expiry date. Trade-off: early detection against occasional pipeline friction |
| AD-27 | Control cost by scaling every ECS service to zero from 02:00 to 18:00 SGT on weekdays with EventBridge Scheduler, plus scripts to stop and start on demand, and an AWS Budget of USD 100/month that emails the whole team. Trade-off: spend stays inside the course budget against the environment being unavailable on weekday daytimes |
| AD-28 | Run a single AWS environment. Local docker-compose (with the same Kong config) and CI (mocked and full-stack end-to-end tests) act as the lower environments. Trade-off: halves cost against no staging environment for release rehearsal (AISS-06) |
| AD-29 | Keep engineering policy in a central repository (`onestage-ai-engineering`): AI-agent skills, rules and reusable GitHub workflows that the application repositories pin by commit SHA. Trade-off: consistent practices for humans and AI agents against setup effort and the need to keep pins current |
| AD-30 | Use separate repositories: `backend-repo` (all services, Kong, Terraform), `core-frontend` (SPA), `onestage-ai-engineering` (policy) and `docs` (design). Trade-off: clear ownership and independent pipelines against changes that span repositories needing coordinated pull requests |

## Rationale

**AD-23 Terraform with manual apply.** The whole stack can be rebuilt from code, and every infrastructure change is reviewed in a pull request. Apply stays manual because the state covers live data stores (EFS and the secret both have `prevent_destroy`), and a bad automated apply could destroy them. The cost is drift: the hand-added MySQL rules (AISS-04) and the Cognito pool (AISS-07) live outside the code.

**AD-24 OIDC deploy roles.** The backend role can push to ECR and update ECS services; the frontend role can write to the frontend bucket and invalidate CloudFront. Each trusts only `repo:nus-mtech-grp1-sem2@*/<repo>@*:ref:refs/heads/main`, so a workflow on a feature branch or a fork cannot deploy. In the deploy workflow, `id-token: write` is granted only to the jobs that need AWS, not to the test job.

**AD-25 Gated rolling deployment.** `deploy-backend.yml` calls `backend-quality.yml` first and builds images only if it passes. A manual run can force a deploy past failing checks only with a written reason, which is recorded; a push to `main` can never force. Images are pushed as `:latest` and as the commit SHA, but services run `:latest`, so a rollback means rebuilding an older commit. Immutable SHA-tagged task definitions and the ECS deployment circuit breaker are the planned improvement.

**AD-26 Security scanning with an accepted-risk process.** Semgrep and the dependency audit run on every push and pull request to `main`; ZAP runs weekly against the deployed site. When `npm audit` began failing on an unpatched `braces` advisory reachable only through a development tool (`nodemon`), the team allowlisted that one advisory on that one path until 31 Dec 2026, with a named owner and a tracking issue (#106). Risks are managed explicitly, not hidden by turning a check off.

**AD-27 Scale to zero and budgets.** Actual spend was USD 16.99 in August and USD 76.00 in September. Because the database is a container (AD-13), the whole platform, data tier included, scales to zero outside working hours. The schedule is a safety net; the team also runs `stop-env.sh` after each session.

**AD-28 Single environment.** Promotion goes local docker-compose → CI (unit tests, mocked end-to-end tests, a weekly full-stack end-to-end run on docker-compose with real Cognito) → AWS. Pull request review is the approval step. A staging environment would double the fixed costs (load balancer, minimum tasks, database task).

**AD-29 Central AI engineering governance.** AI coding agents were used throughout the project. The central repository gives them the same rules a human reviewer would apply (for example `database-migration-review`, `node-service-change`, `pr-readiness`, `k6-load-test`) and supplies reusable CI workflows. Callers pin workflows by full commit SHA, so a change to the central repository cannot alter an application pipeline without a reviewed pin update.

**AD-30 Repository split.** Backend services share one repository because they share one image (AD-01) and one Terraform stack. The frontend deploys independently to S3. Design documents live apart from code so that report material is versioned without triggering builds.
