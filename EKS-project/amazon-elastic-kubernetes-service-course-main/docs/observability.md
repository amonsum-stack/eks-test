# Observability — CloudWatch Alarms + S3 Notifications

---

## What gets monitored

### EKS Nodes → `eks-node-alarms` SNS topic
| Alarm | Threshold | Why |
|-------|-----------|-----|
| `eks-node-cpu-high` | CPU > 90% for 10 min | Node under sustained pressure |
| `eks-node-status-check-failed` | Any status check failure | Node may be unreachable |

### RDS Postgres → `eks-rds-alarms` SNS topic
| Alarm | Threshold | Why |
|-------|-----------|-----|
| `rds-cpu-high` | CPU > 90% for 10 min | Query load or runaway process |
| `rds-storage-low` | Free storage < 4GB | Prevent out-of-disk crash |
| `rds-connections-high` | Connections > 48 (80% of 60 max) | Connection pool exhaustion warning |
| `rds-instance-down` | No metrics for 2 periods | Instance unreachable |

### S3 Backup → `eks-backup-events` SNS topic
| Event | Trigger | Why |
|-------|---------|-----|
| Backup completed | New `.sql.gz` in `backups/` | Confirm weekly backup ran |

---

## Step 1 — Set your email address

Add to `eks/terraform.tfvars` (this file is gitignored):

```hcl
alert_email = "you@example.com"
```

Or export as an environment variable:

```bash
export TF_VAR_alert_email="you@example.com"
```

---

## Step 2 — Apply

```bash
terraform apply
```

---

## Step 3 — Confirm SNS subscriptions

After apply, AWS will send **three confirmation emails** to your address,
one per SNS topic:

- `AWS Notification - Subscription Confirmation` from `eks-node-alarms`
- `AWS Notification - Subscription Confirmation` from `eks-rds-alarms`
- `AWS Notification - Subscription Confirmation` from `eks-backup-events`

**You must click "Confirm subscription" in each email** — until you do,
notifications will not be delivered. Check your spam folder if they
don't arrive within a few minutes.

---

## Step 4 — Verify alarms exist

```bash
aws cloudwatch describe-alarms \
  --alarm-names \
    eks-node-cpu-high \
    eks-node-status-check-failed \
    rds-cpu-high \
    rds-storage-low \
    rds-connections-high \
    rds-instance-down \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}'
```

You should see all alarms in `OK` or `INSUFFICIENT_DATA` state initially.

---

## Step 5 — Test the backup notification

Trigger a manual backup and confirm you receive an email:

```bash
kubectl delete job backup-test -n demo 2>/dev/null || true
kubectl apply -f k8s/backup/backup.yaml
kubectl logs -n demo job/backup-test -f
```

Within ~30 seconds of the job completing you should receive an email
from `eks-backup-events` with subject:
`[AWS Notification] Amazon S3 Notification`

The email body will contain the S3 event JSON showing the object key,
size, and timestamp of the backup file.

Trigger cpu alarms on EKS nodes

kubectl run cpu-stress \
  --image=containerstack/cpustress \
  --namespace=demo \ <whichever ns you created eariler>
  -- --cpu 4 --timeout 600s --metrics-brief

---

## Architecture summary

```
EKS Nodes (EC2 metrics)
  └── CloudWatch Alarm (CPU > 90%, status check failed)
        └── SNS: eks-node-alarms → Email

RDS Postgres (RDS metrics, published automatically)
  └── CloudWatch Alarms (CPU, storage, connections, availability)
        └── SNS: eks-rds-alarms → Email

S3 Backup Bucket
  └── Event Notification (s3:ObjectCreated on backups/*.sql.gz)
        └── SNS: eks-backup-events → Email
```

---

## Design decisions (interview talking points)

- **Separate SNS topics** — different concerns can be routed to
  different teams or escalation paths without changing alarm config
- **ok_actions on every alarm** — you get notified when an alarm
  clears, not just when it fires. Important for knowing when an
  incident is resolved without checking the console
- **treat_missing_data = "breaching" on rds-instance-down** — if
  the RDS instance stops emitting metrics entirely, we treat that
  as a breach rather than ignoring it. Prevents silent failures
- **S3 event notification vs polling** — fires immediately on backup
  completion, not on a schedule. No Lambda needed, no cost beyond
  SNS delivery
- **Alert thresholds** — storage alert at 4GB (20% of 20GB) gives
  meaningful lead time before the instance crashes; connection alert
  at 80% of max gives time to investigate before connections are refused

---

## Cleanup

```bash
terraform destroy
```

Note: SNS subscriptions in `PendingConfirmation` state are automatically
deleted with the topic. Confirmed subscriptions are also removed.
