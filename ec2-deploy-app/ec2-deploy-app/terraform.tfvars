vpc_cidr = "10.0.0.0/16"

vpc_name = "test-vpc"

cidr_subnet_public = ["10.0.1.0/24", "10.0.5.0/24", "10.0.6.0/24"]

cidr_subnet_private = ["10.0.2.0/24", "10.0.3.0/24", "10.0.4.0/24"]

us_availability_zone = ["us-east-1a", "us-east-1b", "us-east-1c"]

ec2_security_group_name = "test-ec2-sg"

ec2_security_group_description = "Security group for EC2 instances"

instance_type = "t2.medium"

lb_target_group_name = "test-lb-target-group"

lb_target_group_port = 8080

lb_target_group_protocol = "HTTP"

lb_name = "test-lb"

lb_type = "application"

lb_listener_port = 80

lb_listener_protocol = "HTTP"

lb_listener_default_action_type = "forward"

db_name = "appdb"

db_username = "appuser"

db_engine = "postgres"

db_instance_class = "db.t3.micro"

alert_email = "hadika4872@deapad.com" #place your email here to receive alerts