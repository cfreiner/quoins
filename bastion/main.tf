/**
* This module creates a bastion instance. The bastion host acts as the
* "jump point" for the rest of the infrastructure. Since most of our
* instances aren't exposed to the external internet, the bastion acts as
* the gatekeeper for any direct SSH access. The bastion is provisioned using
* the key name that you pass to the module (and hopefully have stored somewhere).
* If you ever need to access an instance directly, you can do it by
* "jumping through" the bastion.
*
* Usage:
*
* ```hcl
* module "bastion" {
*   source                = "github.com/concur/quoins//bastion"
*   bastion_ami_id        = "ami-*****"
*   bastion_instance_type = "t2.micro"
*   bastion_key_name      = "ssh-key"
*   security_groups       = "sg-*****,sg-*****"
*   subnet_id             = "pub-1"
*   cost_center           = "1000"
*   role_type             = "abcd"
*   name                  = "quoin-bastion"
* }
* ```
*/

/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "bastion_ami_id" {
  description = "The ID Amazon Machine Image (AMI) to use for the instance."
}

variable "bastion_instance_type" {
  default     = "t2.micro"
  description = "Instance type, see a list at: https://aws.amazon.com/ec2/instance-types/"
}

variable "bastion_key_name" {
  description = "The name of the SSH key pair to use for the bastion."
}

variable "security_group_ids" {
  description = "A comma separated lists of security group IDs"
}

variable "availability_zone" {
  description = "An availability zone to launch the instance."
}

variable "subnet_id" {
  description = "An external subnet id."
}

variable "name" {
  description = "A name to prefix the bastion tag."
}

variable "role_type" {
  description = "The role type to attach resource usage."
}

variable "cost_center" {
  description = "The cost center to attach resource usage."
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Bastion AWS Instance
resource "aws_instance" "bastion" {
  ami                    = "${var.bastion_ami_id}"
  instance_type          = "${var.bastion_instance_type}"
  availability_zone      = "${var.availability_zone}"
  subnet_id              = "${var.subnet_id}"
  key_name               = "${var.bastion_key_name}"
  vpc_security_group_ids = ["${split(",",var.security_group_ids)}"]
  monitoring             = true
  user_data              = "${file(format("%s/user_data.yaml", path.module))}"

  tags {
    Name       = "${var.name}"
    RoleType   = "${var.role_type}"
    CostCenter = "${var.cost_center}"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# Bastion external IP address
output "bastion_external_ip" {
  value = "${aws_instance.bastion.public_ip}"
}
