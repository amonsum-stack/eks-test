variable "vpc_id" {}
variable "security_group_id" {}
variable "lb_name" {}
variable "lb_type" {}
variable "lb_listener_port" {}
variable "lb_listener_protocol" {}
variable "public_subnet_id" {}
variable "lb_listener_default_action_type" {}



resource "aws_lb" "app_lb" {
  name               = var.lb_name
  internal           = false
  load_balancer_type = var.lb_type
  security_groups    = var.security_group_id
  subnets            = var.public_subnet_id

  tags = {
    Name = "app-lb"
  }
}

output "lb_arn" {
  value = aws_lb.app_lb.arn
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = var.lb_listener_port
  protocol          = var.lb_listener_protocol

  default_action {
    type             = var.lb_listener_default_action_type
    target_group_arn = aws_lb_target_group.app_target_group.arn
  }
}
