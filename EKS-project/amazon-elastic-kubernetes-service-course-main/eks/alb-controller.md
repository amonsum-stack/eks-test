# AWS Load Balancer Controller — Setup Guide

This guide walks through deploying the AWS Load Balancer Controller on the `demo-eks`
cluster using IRSA (IAM Roles for Service Accounts), then verifying it with a demo app.

---

## Prerequisites

- Cluster is running and `kubectl get node` shows nodes in `Ready` state
- `helm` v3 installed
- `terraform apply` has been run with the new `alb-controller.tf`

---

## Step 1 — Apply the Terraform changes

From the `eks/` directory:

```bash
terraform apply
```

Note the new output:

```
AlbControllerIrsaRoleArn = "arn:aws:iam::<account-id>:role/eks-alb-controller-irsa"
```

Copy this ARN — you'll need it in the next step.

---

## Step 2 — Edit the Helm values file

Open `eks/alb-controller-values.yaml` and replace the placeholder with the ARN from above:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<account-id>:role/eks-alb-controller-irsa
```

---

## Step 3 — Install the ALB Controller via Helm

```bash
# Add the EKS charts repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  -f eks/alb-controller-values.yaml
```

### Verify the controller is running

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

You should see `2/2` ready replicas. Check logs if not:

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

---

## Step 4 — Deploy the demo app

```bash
kubectl apply -f k8s/demo-app/namespace.yaml
kubectl apply -f k8s/demo-app/deployment.yaml
kubectl apply -f k8s/demo-app/ingress.yaml
```

### Watch the ALB get provisioned

```bash
kubectl get ingress -n demo -w
```

After ~60–90 seconds the `ADDRESS` column will populate with an ALB DNS name:

```
NAME       CLASS    HOSTS   ADDRESS                                          PORTS   AGE
demo-app   <none>   *       k8s-demo-xxx.us-east-1.elb.amazonaws.com         80      90s
```

### Test it

```bash
ALB_URL=$(kubectl get ingress demo-app -n demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$ALB_URL
```

You should see something like:

```html
<h1>demo-app on demo-app-7d6f9b-xkp2q</h1>
```

Run `curl` a few times — the hostname in the response will alternate between your 2 pod replicas,
showing the ALB is load balancing across them.

---

## How IRSA works here (interview talking point)

```
Pod (aws-load-balancer-controller)
  └── Projected ServiceAccount token (signed by EKS OIDC issuer)
        └── sts:AssumeRoleWithWebIdentity
              └── IAM checks: token issuer == registered OIDC provider?
                              sub == system:serviceaccount:kube-system:aws-load-balancer-controller?
                    └── Returns temporary credentials for eks-alb-controller-irsa role
                          └── Controller can now call EC2/ELB APIs to provision the ALB
```

This is more secure than the previous approach (attaching the policy to the node role) because:
- The node role grants the permission to **every pod on every node**
- IRSA grants it to **only this one ServiceAccount** — blast radius is minimised

---

## Cleanup

```bash
kubectl delete -f k8s/demo-app/
helm uninstall aws-load-balancer-controller -n kube-system
terraform destroy
```
