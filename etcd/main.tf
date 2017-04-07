/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "name" {
  description = "The name of your quoin."
}

variable "region" {
  description = "Region where resources will be created."
}

variable "role_type" {
  description = "The role type to attach resource usage."
}

variable "cost_center" {
  description = "The cost center to attach resource usage."
}

variable "kms_key_arn" {
  description = "The arn associated with the encryption key used for encrypting the certificates."
}

variable "root_cert" {
  description = "The root certificate authority that all certificates belong to encoded in base64 format."
}

variable "intermediate_cert" {
  description = "The intermediate certificate authority that all certificates belong to encoded in base64 format."
}

variable "vpc_id" {
  description = "The ID of the VPC to create the resources within."
}

variable "vpc_cidr" {
  description = "A CIDR block for the VPC that specifies the set of IP addresses to use."
}

variable "availability_zones" {
  description = "Comma separated list of availability zones for a region."
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Certificates
resource "aws_s3_bucket_object" "root_cert" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/common/tls/root-ca.pem.enc.base"
  content = "${var.root_cert}"
}

resource "aws_s3_bucket_object" "intermediate_cert" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/common/tls/intermediate-ca.pem.enc.base"
  content = "${var.intermediate_cert}"
}

/*
* ------------------------------------------------------------------------------
* Data Sources
* ------------------------------------------------------------------------------
*/

data "template_file" "s3_cloudconfig_bootstrap" {
  template = "${file(format("%s/bootstrapper/s3-cloudconfig-bootstrap.sh", path.module))}"

  vars {
    name = "${var.name}"
  }
}

# Latest stable CoreOS AMI
data "aws_ami" "coreos_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["CoreOS-stable-*-hvm"]
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# The name of our quoin
output "name" {
  value = "${var.name}"
}

# The region where the quoin lives
output "region" {
  value = "${var.region}"
}

# The CoreOS AMI ID
output "coreos_ami" {
  value = "${data.aws_ami.coreos_ami.id}"
}
