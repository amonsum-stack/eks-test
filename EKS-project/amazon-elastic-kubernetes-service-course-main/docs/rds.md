# RDS Postgres — Setup Guide

This guide walks through deploying a private RDS Postgres 16 instance
accessible from EKS pods, with credentials managed via AWS Secrets Manager.

---

## Architecture

```
Internet → ALB → EKS nodes (public subnets)
                     ↓  port 5432, node SG only
                 RDS Postgres (private subnets, no public access)
```

RDS lives in dedicated private subnets with no route to the internet.
Pods on EKS nodes can reach it because they share the same VPC —
the node security group is the only source allowed inbound on 5432.

---

## Step 1 — Add the random provider to main.tf

The RDS module uses `random_password`. Add this to your `main.tf`:

```hcl
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
```

---

## Step 2 — Apply the Terraform changes

From the `eks/` directory:

```bash
terraform init   # picks up the random provider
terraform apply
```

RDS provisioning takes **5–10 minutes**. Note the outputs:

```
rds_endpoint  = "eks-demo-postgres.xxxx.us-east-1.rds.amazonaws.com:5432"
rds_secret_arn = "arn:aws:secretsmanager:us-east-1:..."
```

---

## Step 3 — Create the Kubernetes Secret

```bash
chmod +x eks/create-db-secret.sh
./eks/create-db-secret.sh
```

This pulls credentials from Secrets Manager and creates a
`postgres-credentials` Secret in the `demo` namespace.

Verify:

```bash
kubectl get secret postgres-credentials -n demo
```

---

## Step 4 — Test the connection from a pod

```bash
kubectl apply -f k8s/db-test/db-test-job.yaml

# Wait for the job to complete
kubectl get job db-connection-test -n demo -w

# Check the output
kubectl logs -n demo job/db-connection-test
```

You should see output like:

```
Testing connection to RDS Postgres...
                          version
----------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc
(1 row)

 current_database | current_user |              now
------------------+--------------+-------------------------------
 appdb            | appuser      | 2026-04-29 18:00:00.000000+00
(1 row)

Connection successful!
```

