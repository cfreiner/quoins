/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "etcd_server_cert" {
  description = "The public certificate to be used by etcd servers encoded in base64 format."
}

variable "etcd_server_key" {
  description = "The private key to be used by etcd servers encoded in base64 format."
}

variable "etcd_client_cert" {
  description = "The public client certificate to be used for authenticating against etcd encoded in base64 format."
}

variable "etcd_client_key" {
  description = "The client private key to be used for authenticating against etcd encoded in base64 format."
}

variable "etcd_peer_cert" {
  description = "The public certificate to be used by etcd peers encoded in base64 format."
}

variable "etcd_peer_key" {
  description = "The private key to be used by etcd peers encoded in base64 format."
}

variable "etcd_instance_type" {
  description = "The type of instance to use for the etcd cluster. Example: 'm3.medium'"
  default     = "m3.medium"
}

variable "etcd_min_size" {
  description = "The minimum size for the etcd cluster. NOTE: Use odd numbers."
  default     = "1"
}

variable "etcd_max_size" {
  description = "The maximum size for the etcd cluster. NOTE: Use odd numbers."
  default     = "9"
}

variable "etcd_desired_capacity" {
  description = "The desired capacity of the etcd cluster. NOTE: Use odd numbers."
  default     = "1"
}

variable "etcd_root_volume_size" {
  description = "Set the desired capacity for the root volume in GB."
  default     = "12"
}

variable "etcd_data_volume_size" {
  description = "Set the desired capacity for the data volume used by etcd in GB."
  default     = "12"
}

/*
* ------------------------------------------------------------------------------
* Modules
* ------------------------------------------------------------------------------
*/

module "etcd" {
  source                = "../etcd"
  name                  = "${format("%s-etcd", var.name)}"
  region                = "${var.region}"
  role_type             = "${var.role_type}"
  cost_center           = "${var.cost_center}"
  vpc_id                = "${var.vpc_id}"
  vpc_cidr              = "${var.vpc_cidr}"
  availability_zones    = "${var.availability_zones}"
  subnet_ids            = "${join(",", aws_subnet.internal.*.id)}"
  kms_key_arn           = "${var.kms_key_arn}"
  key_name              = "${module.key_pair.key_name}"
  root_cert             = "${var.root_cert}"
  intermediate_cert     = "${var.intermediate_cert}"
  etcd_server_cert      = "${var.etcd_server_cert}"
  etcd_server_key       = "${var.etcd_server_key}"
  etcd_client_cert      = "${var.etcd_client_cert}"
  etcd_client_key       = "${var.etcd_client_key}"
  etcd_peer_cert        = "${var.etcd_peer_cert}"
  etcd_peer_key         = "${var.etcd_peer_key}"
  etcd_instance_type    = "${var.etcd_instance_type}"
  etcd_min_size         = "${var.etcd_min_size}"
  etcd_max_size         = "${var.etcd_max_size}"
  etcd_desired_capacity = "${var.etcd_desired_capacity}"
  etcd_root_volume_size = "${var.etcd_root_volume_size}"
  etcd_data_volume_size = "${var.etcd_data_volume_size}"
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# The etcd bastion security group ID
output "etcd_bastion_security_group_id" {
  value = "${module.etcd.bastion_security_group_id}"
}