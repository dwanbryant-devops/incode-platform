# Bootstrap

A one-time stack, applied from a workstation by a human admin. It creates what every other stack depends on:

| Resource | Purpose |
|---|---|
| `incode-tfstate-<account>` S3 bucket | Remote state for all stacks. Versioned, KMS-encrypted, TLS-only, locked with native S3 lock files (`use_lockfile`, so no DynamoDB table). |
| GitHub OIDC provider | Lets GitHub Actions get short-lived AWS credentials. There are no static access keys anywhere. |
| `gha-tf-plan` | `ReadOnlyAccess` plus state lock files. Assumable by PRs and `main` in `incode-platform`. |
| `gha-tf-apply` | Admin with guardrails: it can't modify `gha-*` roles, the OIDC provider or the state bucket, and can't create IAM users or keys. Assumable **only** from the GitHub Environment `dev`, which requires reviewer approval. Add another environment name per extra deployed env. |
| `gha-ecr-push-incode-{ui,api}` | Push to one ECR repository each. Assumable only by a job in the matching app repo's `dev` GitHub Environment, which is restricted to `main`. |

## 0. Account hardening (console, manual)

1. Sign in as root, **enable MFA on root**, and delete any root access keys.
2. Create an admin identity for daily use. Identity Center isn't available here, so use an IAM user whose keys can **only** assume an admin role that requires MFA. Leaked keys alone are useless.
   - **Role `admin`:** trusted entity *This account* with **Require MFA** ticked, `AdministratorAccess`, 4h max session.
   - **User `dwan`:** no console access; an inline policy allowing only `sts:AssumeRole` on `role/admin`; an MFA device; a CLI access key.
   - **`~/.aws/config`:**
     ```ini
     [profile incode-user]
     region = us-east-1

     [profile incode-admin]
     source_profile = incode-user
     role_arn       = arn:aws:iam::<ACCOUNT_ID>:role/admin
     mfa_serial     = arn:aws:iam::<ACCOUNT_ID>:mfa/<device-name>
     region         = us-east-1
     ```
   - Run `aws configure --profile incode-user` (keys), then `aws sts get-caller-identity --profile incode-admin`.
3. **Billing → Budgets:** create a monthly budget (for example $300) with email alerts at 50/80/100%.
4. From here on, stop using root.

## 1. Apply

```sh
export AWS_PROFILE=incode-admin
cd bootstrap
terraform init
terraform apply
```

## 2. Move bootstrap's own state into the bucket

Uncomment the `backend "s3"` block in `versions.tf`, fill in the account ID, then run:

```sh
terraform init -migrate-state
rm terraform.tfstate terraform.tfstate.backup
```

## 3. Wire GitHub

The rule: **credentials that can change AWS live in a GitHub Environment locked to `main`; the read-only plan role is repo-level.** When a job declares `environment: X`, GitHub's OIDC `sub` claim becomes `repo:<org>/<repo>:environment:X`, and that claim is what the trust policies match on.

- **incode-platform**
  - Repository variables: `AWS_PLAN_ROLE_ARN`, `TF_STATE_BUCKET`. Plans run on PRs with no environment and no approval.
  - Environment `dev`: required reviewer (you); deployment branches limited to `main`; variable `AWS_APPLY_ROLE_ARN`.
- **Each app repo**
  - Environment `dev`: deployment branches limited to `main`; variable `AWS_ROLE_ARN`, from `terraform output ecr_push_role_arns`.

Role ARNs aren't secrets. The trust policy, together with the environment's branch rule, is what keeps other repos and branches out.
