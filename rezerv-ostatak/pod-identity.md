# Pod Identity — Setup Guide

EKS Pod Identity is a newer, simpler alternative to IRSA for giving
pods access to AWS services. This guide walks through migrating the
ALB controller and backup job from IRSA to Pod Identity.

---

## IRSA vs Pod Identity — key differences

| | IRSA | Pod Identity |
|---|---|---|
| Requires OIDC provider | Yes | No |
| Trust policy complexity | High (StringEquals conditions) | Low (service principal only) |
| SA annotation required | Yes (role ARN) | No |
| Cluster portability | Role tied to OIDC URL (cluster-specific) | Role reusable across clusters |
| Requires addon | No | Yes (eks-pod-identity-agent) |
| AWS Console visibility | IAM only | EKS Console shows associations |

---

## Architecture comparison

### IRSA flow
```
Pod → projected SA token → STS AssumeRoleWithWebIdentity
  → IAM checks OIDC issuer + sub/aud conditions
    → temporary credentials
```

### Pod Identity flow
```
Pod → credential request to Pod Identity Agent (DaemonSet)
  → Agent calls EKS API with pod's SA token
    → EKS looks up PodIdentityAssociation for namespace/SA
      → returns temporary credentials
```

Pod Identity is simpler because the trust relationship is managed
by EKS directly rather than encoded in IAM trust policy conditions.

---

## Step 1 — Install the Pod Identity Agent addon

### Option A — Terraform (may require eks:CreateAddon permission)

```bash
terraform apply
```

If this fails with AccessDenied, use Option B.

### Option B — AWS Console (if Terraform blocked by lab SCP)

1. Go to EKS → Clusters → demo-eks → Add-ons
2. Click "Get more add-ons"
3. Search for "EKS Pod Identity Agent"
4. Select it and click Next → Next → Create

Verify the addon is running:

```bash
kubectl get daemonset eks-pod-identity-agent -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

You should see 3 pods running (one per node).

---

## Step 2 — Apply the Pod Identity roles and associations

```bash
terraform apply
```

This creates:
- `eks-alb-controller-pod-identity` IAM role
- `eks-backup-pod-identity` IAM role
- Two `aws_eks_pod_identity_association` resources

Verify associations exist:

```bash
aws eks list-pod-identity-associations --cluster-name demo-eks
```

You should see two associations — one for kube-system/aws-load-balancer-controller
and one for demo/backup-job.

---

## Step 3 — Update the ALB controller Helm release

The ServiceAccount annotation (`eks.amazonaws.com/role-arn`) is no
longer needed. Upgrade the Helm release with the new values file:

```bash
helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  -f eks/alb-controller-values-pod-identity.yaml
```

Remove the old annotation from the ServiceAccount:

```bash
kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn-
```

Restart the controller to pick up the new credential source:

```bash
kubectl rollout restart deployment -n kube-system aws-load-balancer-controller
```

---

## Step 4 — Update the backup ServiceAccount

The backup-job ServiceAccount annotation also needs removing.
Re-run setup-backup.sh which will apply the updated manifest
(remove the annotation from backup.yaml first):

```yaml
# backup.yaml ServiceAccount — remove the annotation block entirely
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backup-job
  namespace: demo
  # No annotations needed with Pod Identity
```

---

## Step 5 — Verify everything works

### ALB controller

```bash
# Controller should still be running
kubectl get deployment -n kube-system aws-load-balancer-controller

# Ingress should still have its address
kubectl get ingress -n demo

# Check controller logs for any auth errors
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=20
```

### Backup job

```bash
kubectl delete job backup-test -n demo 2>/dev/null || true
./eks/setup-backup.sh
kubectl logs -n demo job/backup-test -f
```

---

## Viewing associations in the AWS Console

One advantage of Pod Identity over IRSA is visibility in the EKS console:

EKS → Clusters → demo-eks → Access → Pod Identity associations

You can see exactly which namespace/ServiceAccount maps to which IAM role
without having to check IAM trust policies.

---

## Interview talking points

- **No OIDC dependency** — IRSA trust policies embed the OIDC issuer URL,
  making roles cluster-specific. Pod Identity roles can be reused across
  clusters by creating new associations.
- **Simpler trust policy** — just `pods.eks.amazonaws.com` as principal,
  no `StringEquals` conditions to maintain or debug.
- **Better auditability** — associations are visible in the EKS console,
  not buried in IAM trust policies.
- **Same least-privilege outcome** — the IAM policies themselves are
  identical, only the mechanism for assuming the role differs.
- **When to still use IRSA** — cross-account role assumptions, or if
  the cluster is too old to support Pod Identity (requires EKS 1.24+).
