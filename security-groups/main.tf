/*
* This module creates basic security groups to be used by instances.
*
* Usage:
*   module "security_groups" {
*     source = "github.com/concur/quoins//security-groups"
*     vpc_id = "vpc-*****"
*     name   = "quoin"
*   }
*
*   provider "aws" {
*     region = "us-west-2"
*   }
*
*/

/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "name" {
  description = "A name to prefix security groups."
}

variable "vpc_id" {
  description = "The ID of the VPC to create the security groups on."
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# External SSH Security Group
resource "aws_security_group" "external_ssh" {
  name        = "${format("%s-external-ssh", var.name)}"
  description = "Allows ssh from the world."
  vpc_id      = "${var.vpc_id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags {
    Name = "${format("%s-external-ssh", var.name)}"
  }
}

# External Windows Remote Security Group
resource "aws_security_group" "external_win_remote" {
  name        = "${format("%s-external-win-remote", var.name)}"
  description = "Allows Windows Remote from the world."
  vpc_id      = "${var.vpc_id}"

  # RDP
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # WinRM Secure
  ingress {
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # WinRM Insecure
  ingress {
    from_port   = 5985
    to_port     = 5985
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags {
    Name = "${format("%s-external-win-remote", var.name)}"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# External SSH allows ssh connections on port 22
output "external_ssh" {
  value = "${aws_security_group.external_ssh.id}"
}

# External Windows Remote allows remote connections on ports 3389, 5986, & 5985
output "external_win_remote" {
  value = "${aws_security_group.external_win_remote.id}"
}
