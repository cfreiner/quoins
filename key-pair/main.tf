/**
* This module creates a key pair to be used by instances.
*
* Usage:
*
* ```hcl
* module "ssh_key_pair" {
*   source = "github.com/concur/quoins//key-pair"
*   key_name   = "quoin-bastion"
*   public_key = "ssh-rsa skdlfjkljasfkdjjkas;dfjksakj ... email@domain.com"
* }
*
* provider "aws" {
*   region = "us-west-2"
* }
* ```
*
*/

/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "key_name" {
  description = "A name to give the key pair."
}

variable "public_key" {
  description = "Public key material in a format supported by AWS: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#how-to-generate-your-own-key-and-import-it-to-aws"
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# SSH Key Pair
resource "aws_key_pair" "ssh" {
  key_name   = "${var.key_name}"
  public_key = "${var.public_key}"
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# Key name given to key pair
output "key_name" {
  value = "${aws_key_pair.ssh.key_name}"
}

# Fingerprint of given public key
output "fingerprint" {
  value = "${aws_key_pair.ssh.fingerprint}"
}
