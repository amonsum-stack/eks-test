How wheather-app works and how to deploy it, alongside its components and infrastructure

1. EKS-cluster infrastructure

-- modules present in this deployment are needed since this was done in a lab enviroment and sometimes labs would be having issues with roles that exist or are leftovers from previous tries. In a non-lab enviroment modules could be removed and replaced with an iam.tf with the following content:

```
resource "aws_iam_role" "eks_cluster_role" {
  name = "eksClusterRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "eksClusterRole"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# Enables Security Groups for Pods
resource "aws_iam_role_policy_attachment" "eks_vpc_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}
```

-- In the eks.tf replace role_arn

```
resource "aws_eks_cluster" "demo_eks" {
  name     = var.cluster_name
  ---> role_arn = var.use_predefined_role ? module.use_eksClusterRole[0].eksClusterRole_arn : module.create_eksClusterRole[0].eksClusterRole_arn
}
```

-- With this role_arn

```
---> role_arn = aws_iam_role.eks_cluster_role.arn
```

-- In the variables.tf remove the following block 

```
variable "use_predefined_role" {
  type        = bool
  description = "Whether to use predefined cluster service role, or create one."
  default     = false   
}
```


-- Since this is an unmannged cluster we need the file <aws-auth-cm.yaml> updated with instance-role ARN in order to register worker nodes. Don't forget to copy/write all the outputs when terraform apply completes.

-- Also keep in mind the following command <aws eks update-kubeconfig --region us-east-1 --name demo-eks> we need it so kubectl can find the cluster and authenticate with it.

-- There is a cloud watch alarm and sns notification system deployed. You can add your email on which you want to receive sns messages when you go terraform apply. Or you can add it in variables.tf or tfvars file. Or maybe you can use the following command after terraform init <export TF_VAR_alert_email="you@example.com">


2. After terraform is deployed and nodes are in a ready state you can begin deploying other parts of the project.

3. Deploy ALB controller with HELM and <alb-controller-values.yaml>. Ensure HELM is installed and updated.

#   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
#     -n kube-system \
#     -f alb-controller-values.yaml

-- After the deployment check the alb controller pods which should be in the kube-system namespace. Also you can now apply the <ingress-class-name.yaml> so you future ingress files can pull from there.

4. Create "weather" and "demo" namespace with the command 'kubectl create namespace wheater' or declarativley in a file. Demo namespace is probably not needed here, but it can help us out in the next step testing the accesability of the database.

5. Apply the script, use chmod +x <create-db-secret.sh>, the script will create two kubernetes secrets that are needed for accessing the postgres database running on the RDS instance. Apply <db-test-job.yaml> and check the results with "kubectl logs -n demo db-connection-test", you should see database that is created. 

6. Now you can apply <weather.yaml> main file which contains the following.
--
--
--



7. After applying <weather.yaml> you can apply <init-db.yaml> which will initiate and create databases in postgres for weather app. It is important to apply this after the main file since the init-db needs service account from the 'weather-fetcher' which is located in the <weather.yaml>

8. You can now apply <weather-hpa.yaml> for horizontal pod autoscaling. The scaler is working primarly on CPU metrics, and memory as secondery metric. However, before deploying the HPA, check if the metric server is available. 
# kubectl top pods -n weather
# if missing go for kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

8. Although RDS has its own backups, you can apply the script chmod +x <setup-backup.sh> to create a job that will be doing backups from the RDS to S3 bucket, once a week (this can be modified in <backup.yaml>). Bucket is private, SSE, and has lifecycle policy. 

9. Applying prometheus and grafana with the following script chmod +x <setup-prometheus.sh>. This script will deploy prometheus and grafana stack via HELM. Its very convinient since it already has a lot of predefined metrics needed for EKS and its components. Note that in the <prometheus-values.yaml> file you can see the details, including other components of the stack. 
-- Please note that in the values file for prometheus <storageSpec: {}> is empty and <persistence.enabled: false> for grafana. 
-- This is due inability to apply EBS-CSI addon and needed roles.
-- Lab enviroment doesn't allow EBS-CSI so grafana and prometheus are not persistant. And we cannot make PVC. 
-- In a real enviroment EBS-CSI should be installed. 

