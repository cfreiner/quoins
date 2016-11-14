/*
* This module creates a single virtual network and routes traffic in and out of
* the network by creating an internet gateway within a given region.
*
* Usage:
*   module "network" {
*     source = "github.com/concur/quoins//network"
*     cidr   = "172.16.0.0/16"
*     name   = "prod-us-network"
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

variable "cidr" {
  description = "A CIDR block for the network."
  default     = "172.16.0.0/16"
}

variable "enable_dns_support" {
  description = "Enable/Disable DNS support in the VPC."
  default     = "true"
}

variable "enable_dns_hostnames" {
  description = "Enable/Disable DNS hostnames in the VPC."
  default     = "true"
}

variable "name" {
  description = "A name to tag the network."
  default     = "quoin-network"
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Network
resource "aws_vpc" "main" {
  cidr_block           = "${var.cidr}"
  enable_dns_support   = "${var.enable_dns_support}"
  enable_dns_hostnames = "${var.enable_dns_hostnames}"

  tags {
    Name = "${var.name}"
  }
}

# Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "${var.name}"
  }
}

# Route Tables
resource "aws_route_table" "external" {
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.main.id}"
  }

  tags {
    Name = "${var.name}-external"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# The Network ID
output "vpc_id" {
  value = "${aws_vpc.main.id}"
}

# The CIDR used for the network
output "vpc_cidr" {
  value = "${var.cidr}"
}

# The Network Security Group ID
output "default_security_group_id" {
  value = "${aws_vpc.main.default_security_group_id}"
}

# The Internet Gateway ID
output "internet_gateway_id" {
  value = "${aws_internet_gateway.main.id}"
}
