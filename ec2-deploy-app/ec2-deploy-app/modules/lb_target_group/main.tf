variable "vpc_id" {}
variable "lb_arn" {}                          
variable "lb_target_group_name" {}
variable "lb_target_group_port" {}
variable "lb_target_group_protocol" {}
variable "lb_listener_port" {}                
variable "lb_listener_protocol" {}            
variable "lb_listener_default_action_type" {} 
variable "ec2_instance_ids" {}  

output "lb_target_group_arn" {
  value = aws_lb_target_group.app_target_group.arn
}


#LB target group
resource "aws_lb_target_group" "app_target_group" {
  name     = var.lb_target_group_name
  port     = var.lb_target_group_port
  protocol = var.lb_target_group_protocol
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# Attach EC2 instances to the target group
resource "aws_lb_target_group_attachment" "ec2_instances" {
  count            = length(var.ec2_instance_ids)
  target_group_arn = aws_lb_target_group.app_target_group.arn
  target_id        = var.ec2_instance_ids[count.index]
  port             = var.lb_target_group_port
}

# Create a listener for the load balancer
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = var.lb_arn
  port              = var.lb_listener_port
  protocol          = var.lb_listener_protocol

  default_action {
    type             = var.lb_listener_default_action_type
    target_group_arn = aws_lb_target_group.app_target_group.arn
  }
}