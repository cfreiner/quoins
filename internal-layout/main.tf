/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "vpc_id" {
  description = "The ID of the VPC to create the resources within."
}

variable "availability_zones" {
  description = "Comma separated list of availability zones for a region."
}

variable "internal_subnets" {
  description = "Comma separated list of CIDR's to use for the internal subnets."
}

variable "name" {
  description = "A name to tag the resources."
}

variable "k8_cluster_name" {
  description = "The name of your k8 cluster name, i.e. your Kubernetes quoin name"
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Subnets
resource "aws_subnet" "internal" {
  vpc_id            = "${var.vpc_id}"
  cidr_block        = "${element(split(",", var.internal_subnets), count.index)}"
  availability_zone = "${element(split(",", var.availability_zones), count.index)}"
  count             = "${length(compact(split(",", var.internal_subnets)))}"

  tags {
    Name              = "${var.name}-${format("internal-%03d", count.index+1)}"
    KubernetesCluster = "${var.k8_cluster_name}"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# A comma-separated list of availability zones for the network.
output "availability_zones" {
  value = "${join(",", aws_subnet.internal.*.availability_zone)}"
}

# A comma-separated list of subnet ids for the internal subnets.
output "internal_subnet_ids" {
  value = "${join(",", aws_subnet.internal.*.id)}"
}
