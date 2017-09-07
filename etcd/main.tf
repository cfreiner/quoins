/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "name" {
  description = "The name of your quoin."
}

variable "version" {
  description = "The version number of your infrastructure, used to aid in zero downtime deployments of new infrastructure."
  default     = "latest"
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

variable "tls_provision" {
  description = "The TLS ca and assets provision script."
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

variable "assume_role_principal_service" {
  description = "Principal service used for assume role policy. More information can be found at https://docs.aws.amazon.com/general/latest/gr/rande.html#iam_region."
  default     = "ec2.amazonaws.com"
}

variable "arn_region" {
  description = "Amazon Resource Name based on region, aws for most regions and aws-cn for Beijing"
  default = "aws"  
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Certificates Provision Script
resource "aws_s3_bucket_object" "tls_provision" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/common/tls/tls-provision.sh"
  content = "${var.tls_provision}"
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

data "template_file" "assume_role_policy" {
  template = "${file(format("%s/policies/assume-role-policy.json", path.module))}"

  vars {
    assume_role_principal_service = "${var.assume_role_principal_service}"
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
