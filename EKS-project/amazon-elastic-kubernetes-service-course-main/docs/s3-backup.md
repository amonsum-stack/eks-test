# S3 Backup — Setup Guide

Weekly `pg_dump` of RDS Postgres, streamed directly to S3,
with automatic Glacier archiving after 30 days.

---

## Architecture

```
CronJob (every Sunday 02:00 UTC)
  └── pg_dump | gzip
        └── aws s3 cp (streamed, no local disk)
              └── S3 bucket (Standard)
                    └── Lifecycle: → Glacier IR after 30 days
                                   → Delete after 365 days
```

IRSA ensures the backup pod has S3 write access without any
static AWS credentials in the cluster.

---

## Step 1 — Apply Terraform

```bash
terraform apply
```

Note the new outputs:

```
backup_bucket_name   = "demo-eks-db-backups-123456789012"
backup_irsa_role_arn = "arn:aws:iam::...:role/eks-backup-irsa"
```

---

## Step 2 — Deploy the ServiceAccount and CronJob

```bash
chmod +x eks/setup-backup.sh
./eks/setup-backup.sh
```

This patches the manifest with your real bucket name and role ARN,
then applies the ServiceAccount and CronJob to the cluster.

Verify:

```bash
kubectl get serviceaccount backup-job -n demo
kubectl get cronjob postgres-backup -n demo
```

---

## Step 3 — Test immediately

Rather than waiting until Sunday, trigger the test Job:

```bash
kubectl apply -f backup.yaml
```

Watch it run:

```bash
kubectl get job backup-test -n demo -w
```

Check the output:

```bash
kubectl logs -n demo job/backup-test
```

You should see:

```
Starting test backup for 2026-04-30...
Target: s3://demo-eks-db-backups-123456789012/backups/2026-04-30/appdb-test.sql.gz
Upload complete. Verifying...
2026-04-30 07:00:01      12345 backups/2026-04-30/appdb-test.sql.gz
Test backup successful!
```

Verify in AWS console or via CLI:

```bash
aws s3 ls s3://$(terraform output -raw backup_bucket_name)/backups/ --recursive
```

---

## Lifecycle policy explained

| Days | Storage class | Cost vs Standard |
|------|--------------|-----------------|
| 0–30 | S3 Standard | Baseline |
| 30–365 | Glacier Instant Retrieval | ~68% cheaper |
| 365+ | Deleted | — |

Glacier Instant Retrieval is the right choice here over regular Glacier
because retrieval is in milliseconds rather than hours — important if
you ever need to do an emergency restore.

---

## Design decisions (interview talking points)

- **Streamed directly to S3** — `pg_dump | gzip | aws s3 cp -` pipes
  directly without writing to local disk, so no PVC needed for the Job
- **IRSA scoped to one ServiceAccount** — the backup role only has
  `s3:PutObject` on `backups/*` prefix, nothing else
- **`concurrencyPolicy: Forbid`** — prevents backup jobs overlapping
  if one runs long
- **`--expected-bucket-owner`** — prevents confused deputy attacks
  where a misconfigured bucket name could write to someone else's bucket
- **Versioning enabled** — if a backup job overwrites an existing key,
  the old version is retained

---

## Cleanup

```bash
kubectl delete job backup-test -n demo
kubectl delete cronjob postgres-backup -n demo
kubectl delete serviceaccount backup-job -n demo
terraform destroy
```
