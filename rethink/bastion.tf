/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Security Group for Bastion instances to use
# Bastions are on-demand when needed.
# The vpc variables are declared in main.tf
resource "aws_security_group" "bastion" {
  name   = "${format("%s-bastion-%s", var.name, element(split("-", var.vpc_id), 1))}"
  vpc_id = "${var.vpc_id}"

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.name}-bastion"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# The bastion security group ID
output "bastion_security_group_id" {
  value = "${aws_security_group.bastion.id}"
}