/*
* This module creates a network layout with the following resources
* inside a network:
*
* 1. An external subnet for each availability zone in a region.
* 2. An internal subnet for each availability zone in a region.
* 3. An nat gateway to route traffic from the internal subnets to the internet.
*
* Usage:
*   module "network_layout" {
*     source              = "github.com/concur/quoins//external-internal-layout"
*     vpc_id              = "vpc-*****"
*     internet_gateway_id = "igw-*****"
*     availability_zones  = "us-west-2a,us-west-2b,us-west-2c"
*     external_subnets    = "172.16.0.0/24,172.16.1.0/24,172.16.2.0/24"
*     internal_subnets    = "172.16.3.0/24,172.16.4.0/24,172.16.5.0/24"
*     name                = "prod-us-network-layout"
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

variable "vpc_id" {
  description = "The ID of the VPC to create the resources within."
}

variable "internet_gateway_id" {
  description = "The ID of the internet gateway that belongs to the VPC."
}

variable "availability_zones" {
  description = "Comma separated list of availability zones for a region."
}

variable "external_subnets" {
  description = "Comma separated list of CIDR's to use for the external subnets."
}

variable "internal_subnets" {
  description = "Comma separated list of CIDR's to use for the internal subnets."
}

variable "name" {
  description = "A name to tag the resources."
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Subnets
resource "aws_subnet" "external" {
  vpc_id                  = "${var.vpc_id}"
  cidr_block              = "${element(split(",", var.external_subnets), count.index)}"
  availability_zone       = "${element(split(",", var.availability_zones), count.index)}"
  count                   = "${length(compact(split(",", var.availability_zones)))}"
  map_public_ip_on_launch = true

  tags {
    Name = "${var.name}-${format("external-%03d", count.index+1)}"
  }
}

resource "aws_subnet" "internal" {
  vpc_id            = "${var.vpc_id}"
  cidr_block        = "${element(split(",", var.internal_subnets), count.index)}"
  availability_zone = "${element(split(",", var.availability_zones), count.index)}"
  count             = "${length(compact(split(",", var.availability_zones)))}"

  tags {
    Name = "${var.name}-${format("internal-%03d", count.index+1)}"
  }
}

# NAT Gateway
resource "aws_eip" "nat" {
  count = "${length(compact(split(",", var.internal_subnets)))}"
  vpc   = true
}

resource "aws_nat_gateway" "main" {
  count         = "${length(compact(split(",", var.internal_subnets)))}"
  allocation_id = "${element(aws_eip.nat.*.id, count.index)}"
  subnet_id     = "${element(aws_subnet.external.*.id, count.index)}"
}

# Route Tables
resource "aws_route_table" "external" {
  vpc_id = "${var.vpc_id}"

  tags {
    Name = "${var.name}-external-001"
  }
}

resource "aws_route_table" "internal" {
  count  = "${length(compact(split(",", var.internal_subnets)))}"
  vpc_id = "${var.vpc_id}"

  tags {
    Name = "${var.name}-${format("internal-%03d", count.index+1)}"
  }
}

# Routes
resource "aws_route" "external" {
  route_table_id         = "${aws_route_table.external.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${var.internet_gateway_id}"
}

resource "aws_route" "internal" {
  count                  = "${length(compact(split(",", var.internal_subnets)))}"
  route_table_id         = "${element(aws_route_table.internal.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${element(aws_nat_gateway.main.*.id, count.index)}"
}

# Route Associations
resource "aws_route_table_association" "external" {
  count          = "${length(compact(split(",", var.external_subnets)))}"
  subnet_id      = "${element(aws_subnet.external.*.id, count.index)}"
  route_table_id = "${aws_route_table.external.id}"
}

resource "aws_route_table_association" "internal" {
  count          = "${length(compact(split(",", var.internal_subnets)))}"
  subnet_id      = "${element(aws_subnet.internal.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.internal.*.id, count.index)}"
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# A comma-separated list of availability zones for the network.
output "availability_zones" {
  value = "${join(",", aws_subnet.external.*.availability_zone)}"
}

# A comma-separated list of subnet ids for the external subnets.
output "external_subnet_ids" {
  value = "${join(",", aws_subnet.external.*.id)}"
}

# The external route table ID.
output "external_rtb_id" {
  value = "${aws_route_table.external.id}"
}

# A comma-separated list of subnet ids for the internal subnets.
output "internal_subnet_ids" {
  value = "${join(",", aws_subnet.internal.*.id)}"
}

# The internal route table ID.
output "internal_rtb_ids" {
  value = "${join(",", aws_route_table.internal.*.id)}"
}
