####################################################################
#
# Container Insights — IAM Setup
#
# The CloudWatch agent DaemonSet runs on every node using the
# node instance role (no IRSA needed — it's a system-level agent,
# not an application pod).
#
# Required policy: CloudWatchAgentServerPolicy
# This allows the agent to:
#   - PutMetricData      → push metrics to CloudWatch
#   - CreateLogGroup     → create log groups
#   - CreateLogStream    → create log streams
#   - PutLogEvents       → push container logs
#   - DescribeTags       → read EC2 tags for metric dimensions
#
####################################################################

resource "aws_iam_role_policy_attachment" "node_cloudwatch_agent" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.node_instance_role.name
}
