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

-- There is a cloud watch alarm and sns notification system deployed. You can add your email on which you want to receive sns messages when you go terraform apply. Or you can add it in variables.tf or tfvars file. Or maybe you can use the following command after terraform init <export TF_VAR_alert_email="you@example.com">. SNS is for cloudwatch alarms as well as S3 notification which can notify us when the files are being stored on S3. 


2. After terraform is deployed and nodes are in a ready state you can begin deploying other parts of the project.

3. Deploy ALB controller with HELM and <alb-controller-values.yaml>. Ensure HELM is installed and updated. 
-- NOTE: in the values file add the AlbControllerIrsaRoleArn on <annotations.eks.amazonaws.com/role-arn: Irsa role arn added>

#   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
#     -n kube-system \
#     -f alb-controller-values.yaml

-- After the deployment check the alb controller pods which should be in the kube-system namespace. Also you can now apply the <ingress-class-name.yaml> so you future ingress files can pull from there.

4. Create "weather" and "demo" namespace with the command 'kubectl create namespace wheater' or declarativley in a file. Demo namespace is probably not needed here, but it can help us out in the next step testing the accesability of the database.

5. Apply the script, use chmod +x <create-db-secret.sh>, the script will create two kubernetes secrets that are needed for accessing the postgres database running on the RDS instance. Apply <db-test-job.yaml> and check the results with "kubectl logs -n demo job/db-connection-test", you should see database that is created. 

6. Now you can apply <weather.yaml> main file which contains the following.
-- Namespace, although not needed since it is implemented eariler, but it keeps things originized.
-- Two service accounts, for app and fetcher that gets the data which is used by the app
-- Two roles, one for writing the data with config map and the other for reading the data
-- Role bindings, one that goes to the crone job that writes the data and the other that goes to flask that reads the data
-- Cron job that fetches the data from open meteo, using "weather-fetcher.py" inside the image. Runs every 10 min
-- Cron job hourly agregator, this was added later, since i thought that it would be nice addition to have hourly data agregated in the RDS. Not needed esentially. Using "weather-aggregator.py".
-- Deployment of the app. Important to note is the affinity setting allowing us to place 1 pod across each node. 
-- Service.type.ClusterIP - we are using this since we are already implementing aws ALB controller that is routing via 'target-type: ip' that goes directly to the PODs. The ALB controller actually gets the info from the ingress finds the pods with Service selector and then register their ip as ALB target group. The most important part in the kubernetes service here is the Selector since that points to the correct pods. Using service type LoadBalancer would probably deploy new load balancer per service i think (didn't test it).
-- Finally ingress allows us to provision ALB via controllers (marked with ingressClassName) and bind them to this deployment. Ingress tells us its http traffic with "catch all" prefix /. Backend show where the traffic is routed with the service.

Something about the app. The app is a light-weight python app that display some weather parameters for Belgrade Serbia. It works along with featcher.py which pulls data from the open-meteo api and agregator.py that agregates avarage values every hour for the RDS. Important part of the app is the fetcher.py and cronjob that utilizies this to write new data to a config map that is being injected into the system, so the data stays updated.


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

10. Adding network policies with <network-policies.yaml> will restrict pod traffic and how pods communicate. It is recomended to use aws vpc cni with optional configuration settings {"enableNetworkPolicy": "true"}, Ive added the addon via web UI, since the lab doesn't allow modifications with cli. If you manage to get it with cli or terraform it should work as well. 
# NOTE that trying to get network policies to work with other CNIs like Calico can cause some trouble. Im not 100% sure but when deploying the cluster i presume aws cni is by defult managing network conecctions between pods and nodes. Installing calico or calico policies can cause trouble since caliclo is making virtual interfaces like <cali*> while aws cni already names them <eni*>. I tried changing these setting with caliclo but without sucess, it ended in deleteing and redeploying the nodes. 
-- Look at the details in the network-policies.yaml regarding some specifics that could change in your deployment

-- Commands that can help you with testing these:
- kubectl run test-pod --image=curlimages/curl -n weather --rm -it -- sh | then use curl --max-time 5 http://<fetcher-pod-ip>:8080
- In order to get fetcher pod ip you can use kubectl get pods -n weather -o wide | grep fetcher


-- We can test if the pods can go outside with kubectl run test-pod --image=curlimages/curl -n weather --rm -it -- sh and curl --max-time 5 https://google.com


-- To test connectivity to RDS we can:
-- > terraform output rds_endpoint  and then 
kubectl exec -n weather -it $(kubectl get pods -n weather -l app=weather-app -o jsonpath='{.items[0].metadata.name}') -- python3 -c "
import psycopg2, os
conn = psycopg2.connect(
    host='$(terraform output -raw rds_endpoint | cut -d: -f1)',
    port=5432,
    dbname='appdb',
    user='appuser',
    password='test',
    connect_timeout=5
)
print('Connected successfully!')
conn.close()
"
# The above command should show us that weather-app pods are going to RDS

-- For unlabeled pods that cannot reach rds:
kubectl run rds-test --image=postgres:16-alpine -n weather --rm -it -- sh
- once inside go for psql -h <rds-endpoint> -U appuser -d appdb -c "SELECT 1;" --connect-timeout=5

-- For pods in different namespace that cannot reach rds:
kubectl run rds-test --image=postgres:16-alpine -n default --rm -it -- sh
- once inside go for psql -h <rds-endpoint> -U appuser -d appdb -c "SELECT 1;" --connect-timeout=5



