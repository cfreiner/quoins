/**
* This module creates an elastic load balancer to be used by instances for exposing services.
*
* Usage:
*
* ```hcl
* module "elb-unsecure" {
*   source        = "github.com/concur/quoins//elb-external"
*   name          = "elb-unsecure"
*   vpc_id        = "vpc-123456"
*   subnet_ids    = "subnet-123456,subnet-123457,subnet-123458"
*   lb_port       = "80"
*   instance_port = "30000"
*   healthcheck   = "/health"
*   protocol      = "HTTP"
* }

* module "elb-secure" {
*   source             = "github.com/concur/quoins//elb-external"
*   name               = "elb-secure"
*   vpc_id             = "vpc-123456"
*   subnet_ids         = "subnet-123456,subnet-123457,subnet-123458"
*   lb_port            = "443"
*   instance_port      = "30000"
*   healthcheck        = "/health"
*   protocol           = "HTTPS"
*   ssl_certificate_id = "arn:aws:..."
* }

* provider "aws" {
*   region = "us-west-2"
* }
* ```
*/

/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "name" {
  description = "ELB name, e.g cdn"
}

variable "vpc_id" {
  description = "The ID of the VPC to create the resources within."
}

variable "subnet_ids" {
  description = "Comma separated list of subnet IDs"
}

variable "lb_port" {
  description = "Load balancer port"
}

variable "instance_port" {
  description = "Instance port"
}

variable "healthcheck" {
  description = "Healthcheck path"
}

variable "protocol" {
  description = "Protocol to use, HTTP or TCP"
}

variable "ssl_certificate_id" {
  description = "The ARN of an SSL certificate you have uploaded to AWS IAM."
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

resource "aws_security_group" "external_elb" {
  name        = "${format("%s-external-elb", var.name)}"
  vpc_id      = "${var.vpc_id}"
  description = "Allows external ELB traffic"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags {
    Name = "${format("%s-external-elb", var.name)}"
  }
}

resource "aws_elb" "external" {
  name = "${var.name}"

  internal                  = false
  cross_zone_load_balancing = true
  subnets                   = ["${split(",", var.subnet_ids)}"]
  security_groups           = ["${aws_security_group.external_elb.id}"]

  idle_timeout                = 60
  connection_draining         = true
  connection_draining_timeout = 15

  listener {
    lb_port            = "${var.lb_port}"
    lb_protocol        = "${var.protocol}"
    instance_port      = "${var.instance_port}"
    instance_protocol  = "${var.protocol}"
    ssl_certificate_id = "${var.ssl_certificate_id}"
  }

  health_check {
    healthy_threshold   = 10
    unhealthy_threshold = 2
    timeout             = 5
    target              = "${var.protocol}:${var.instance_port}${var.healthcheck}"
    interval            = 30
  }

  tags {
    Name = "${var.name}-balancer"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# The ELB name.
output "name" {
  value = "${aws_elb.external.name}"
}

# The ELB ID.
output "id" {
  value = "${aws_elb.external.id}"
}

# The ELB dns_name.
output "dns" {
  value = "${aws_elb.external.dns_name}"
}
