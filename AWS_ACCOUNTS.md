# AWS Accounts Reference

Cross-project record of AWS account ownership, IAM users, and their purpose —
covering `cluo`, `homelab`, `germinal`, and `leviosa`. Written after the 2026
account reorganization (see cluo's `.local/prd/aws-account-reorganization.md`
for the project history). Cross-checked against the live state of
`~/.aws/credentials` / `~/.aws/config` and the accounts themselves at time of
writing — not a plan, this reflects what's actually deployed.

If this drifts from reality again, re-derive it the same way: `aws sts
get-caller-identity --profile <name>` per profile, then `aws iam list-users`
+ `list-attached-user-policies` per account.

## Account `970547355404` — personal account

Hosts: **homelab**, **cluo**.

| IAM user | Purpose | Scoped to | `~/.aws` profile |
|---|---|---|---|
| `henga` | Personal admin (`AdministratorAccess`). Backs the `default` profile. Replaces the old `leviosa`-named admin user, retired during this reorg. | Full account access — use deliberately, not as an implicit fallback. | `default` |
| `terraform-homelab` | Terraform admin for homelab. | homelab's Terraform-managed resources (VPS, DNS, S3 backup bucket, IAM). | `terraform-homelab` |
| `terraform-cluo` | Terraform admin for cluo. | `cluo-*`-named resources only (S3/CloudFront/ACM/SES/KMS, plus IAM create/tag for `cluo-*` users). | `terraform-cluo` |
| `cluo-app` | Least-privilege runtime credential for cluo (e.g. `make release-desktop` uploads). | `cluo-assets-prod` bucket only — Get/Put/Delete/List, no other permissions. | `cluo-app` |
| `homelab-vaultwarden-backup` | Pre-existing, predates this reorg. Used by the nightly Vaultwarden backup cron (see homelab's `CONTEXT.md` → Backup). | `homelab-backups-henga` bucket. | not in `~/.aws/credentials` — used directly inside the backup container, not from a developer's CLI. |
| `leviosa-bucket` | **Orphaned, not part of any current project's credential set.** AWS has `AWSCompromisedKeyQuarantineV3` attached to this user, and its access key is still listed `Active`. Likely the user that originally owned the two now-deleted orphaned leviosa buckets (see below). | Unknown — not investigated further as part of this doc. | not in `~/.aws/credentials` |

Buckets: `cluo-assets-prod` (cluo production assets, public-read on
`staging/desktop/*`), `homelab-backups-henga` (nightly Vaultwarden backup).

**Known issue:** `leviosa-bucket`'s quarantined-but-active key has not been
investigated or cleaned up. Treat as a live finding, not a planned task —
nobody has decided whether to deactivate/delete it yet.

## Account `164138973060` — brother's account

Hosts: **germinal**, **leviosa**.

| IAM user | Purpose | Scoped to | `~/.aws` profile |
|---|---|---|---|
| `terraform-germinal` | Terraform admin for germinal. Broad scope, unchanged by this reorg. | germinal's Terraform-managed resources. | `terraform-germinal` |
| `terraform-leviosa` | Terraform admin for leviosa. Broad scope, unchanged by this reorg. | leviosa's Terraform-managed resources. | `terraform-leviosa` |
| `app-germinal` | Least-privilege runtime user created by this reorg, intended as germinal's app credential going forward. | `production-germinal-media`, `production-germinal-backups`, `staging-germinal-media`, `staging-germinal-backups` (S3 only). | `app-germinal` |
| `app-leviosa` | Least-privilege runtime user created by this reorg, intended as leviosa's app credential going forward. | `production-leviosa-assets-lc`, `staging-leviosa-assets`, `staging-leviosa-backups` (S3 only). | `app-leviosa` |
| `production-germinal-app`, `staging-germinal-app` | Pre-existing, per-environment app runtime users already in use by the deployed germinal app. Each has its own S3 + SES-send + backup-access policy. | Own environment's germinal resources. | not in `~/.aws/credentials` |
| `production-leviosa-app`, `staging-leviosa-app` | Pre-existing, per-environment app runtime users already in use by the deployed leviosa app. | Own environment's leviosa resources. | not in `~/.aws/credentials` |
| `staging-leviosa-loki-s3-uploader` | Pre-existing. Uploads leviosa staging's Loki logs to S3. | Presumed scoped to a log bucket — not verified as part of this doc. | not in `~/.aws/credentials` |
| `vault-unseal` | Pre-existing. Used for HashiCorp Vault auto-unseal. | Not verified as part of this doc. | not in `~/.aws/credentials` |

Buckets: `germinal-terraform-state`, `leviosa-terraform-state`,
`production-germinal-media`, `production-germinal-backups`,
`staging-germinal-media`, `staging-germinal-backups`,
`production-leviosa-assets-lc`, `staging-leviosa-assets`,
`staging-leviosa-backups`.

**Open question, not resolved by this reorg:** `app-germinal`/`app-leviosa`
(new) and `production-*-app`/`staging-*-app` (pre-existing) both look like
"app runtime" credentials for the same two projects, but nothing here
reconciles them — it's not documented whether the new users are meant to
replace the per-environment ones, run alongside them, or were created
without awareness the old ones existed. Don't assume either way; confirm
before changing what either app actually authenticates with.

## Account `575210791581` — decommissioned, unused

Not assigned to any project. Originally where cluo's `terraform-cluo`
profile pointed before being corrected to `970547355404`. The account is
otherwise empty. Its old `terraform-cluo` IAM user/key were never deleted —
no credentials exist anywhere to authenticate and do so, and the account's
ownership is unidentified (not tied to any known email; possibly a
previously banned AWS account). Decision: leave it alone indefinitely,
don't pursue identifying it further.

## Notes on this doc's accuracy

- The two orphaned leviosa buckets originally planned for deletion
  (`production-leviosa-assets`, `staging-leviosa-terraform-state`) are
  already gone from `970547355404`'s bucket list as of this writing, even
  though the tracking issue for that deletion was never marked closed in
  cluo's `.local/issues/`. Reflects reality here; the issue file itself is
  stale and should be marked done separately.
- `~/.aws/config` had two bugs fixed alongside writing this doc: the
  `terraform-germinal` section was missing the required `profile ` prefix
  (so its region was silently not being picked up by the AWS CLI/SDK), and
  `terraform-leviosa` had no config section at all. Both now have a
  `[profile ...]` block with the correct region (`eu-west-3` for germinal,
  `eu-central-1` for leviosa, matching their buckets' actual regions).
