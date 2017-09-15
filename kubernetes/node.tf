/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/
variable "node_instance_type" {
  description = "The type of instance to use for the node cluster. Example: 'm3.medium'"
  default     = "m3.medium"
}

variable "node_min_size" {
  description = "The minimum size for the node cluster."
  default     = "1"
}

variable "node_max_size" {
  description = "The maximum size for the node cluster."
  default     = "12"
}

variable "node_desired_capacity" {
  description = "The desired capacity of the node cluster."
  default     = "1"
}

variable "node_root_volume_size" {
  description = "Set the desired capacity for the root volume in GB."
  default     = "12"
}

variable "node_docker_volume_size" {
  description = "Set the desired capacity for the docker volume in GB."
  default     = "12"
}

variable "node_data_volume_size" {
  description = "Set the desired capacity for the data volume in GB."
  default     = "12"
}

variable "node_logging_volume_size" {
  description = "Set the desired capacity for the logging volume in GB."
  default     = "12"
}

variable "node_encrypt_docker_volume" {
  description = "Encrypt docker volume used by node."
  default     = true
}

variable "node_encrypt_data_volume" {
  description = "Encrypt data volume used by node."
  default     = true
}

variable "node_encrypt_logging_volume" {
  description = "Encrypt logging volume used by node."
  default     = true
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Auto Scaling Group and Launch Configuration
resource "aws_autoscaling_group" "node" {
  name                 = "${format("%s-node", var.name)}"
  min_size             = "${var.node_min_size}"
  max_size             = "${var.node_max_size}"
  desired_capacity     = "${var.node_desired_capacity}"
  availability_zones   = ["${split(",", var.availability_zones)}"]
  vpc_zone_identifier  = ["${split(",", var.internal_subnet_ids)}"]
  health_check_type    = "EC2"
  force_delete         = true
  launch_configuration = "${aws_launch_configuration.node.name}"

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "${format("%s-node", var.name)}"
    propagate_at_launch = true
  }

  tag {
    key                 = "RoleType"
    value               = "${var.role_type}"
    propagate_at_launch = true
  }

  tag {
    key                 = "CostCenter"
    value               = "${var.cost_center}"
    propagate_at_launch = true
  }

  tag {
    key                 = "KubernetesCluster"
    value               = "${var.name}"
    propagate_at_launch = true
  }
}

resource "aws_launch_configuration" "node" {
  name_prefix          = "${format("%s-node-", var.name)}"
  image_id             = "${data.aws_ami.coreos_ami.id}"
  instance_type        = "${var.node_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.node.name}"
  security_groups      = ["${aws_security_group.kubernetes.id}"]
  key_name             = "${module.key_pair.key_name}"
  depends_on           = ["aws_s3_bucket.cluster", "aws_autoscaling_group.controller", "aws_launch_configuration.controller", "aws_s3_bucket_object.node", "aws_iam_instance_profile.node", "aws_security_group.kubernetes"]

  lifecycle {
    create_before_destroy = true
  }

  # /root
  root_block_device = {
    volume_type = "gp2"
    volume_size = "${var.node_root_volume_size}"
  }

  # /var/lib/docker
  ebs_block_device = {
    device_name = "/dev/sdf"
    encrypted   = "${var.node_encrypt_docker_volume}"
    volume_type = "gp2"
    volume_size = "${var.node_docker_volume_size}"
  }

  # /opt/data
  ebs_block_device = {
    device_name = "/dev/sdg"
    encrypted   = "${var.node_encrypt_data_volume}"
    volume_type = "gp2"
    volume_size = "${var.node_data_volume_size}"
  }

  # /opt/logging
  ebs_block_device = {
    device_name = "/dev/sdh"
    encrypted   = "${var.node_encrypt_logging_volume}"
    volume_type = "gp2"
    volume_size = "${var.node_logging_volume_size}"
  }

  user_data = "${data.template_file.s3_cloudconfig_bootstrap.rendered}"
}

# Node cloud-config
resource "aws_s3_bucket_object" "node" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/node/cloud-config.yaml"
  content = "${data.template_file.node.rendered}"
}

# Profile, Role, and Policy
resource "aws_iam_instance_profile" "node" {
  name       = "${format("%s-node-%s-%s", var.name, var.region, var.version)}"
  roles      = ["${aws_iam_role.node.name}"]
  depends_on = ["aws_iam_role.node", "aws_iam_role_policy.node_policy"]
}

resource "aws_iam_role_policy" "node_policy" {
  name       = "${format("%s-node-policy", var.name)}"
  role       = "${aws_iam_role.node.id}"
  policy     = "${data.template_file.node_policy.rendered}"
  depends_on = ["aws_iam_role.node", "data.template_file.node_policy"]
}

resource "aws_iam_role" "node" {
  name               = "${format("%s-node-%s-%s", var.name, var.region, var.version)}"
  path               = "/"
  assume_role_policy = "${data.template_file.assume_role_policy.rendered}"
}

/*
* ------------------------------------------------------------------------------
* Data Sources
* ------------------------------------------------------------------------------
*/

# Templates
data "template_file" "node_policy" {
  template = "${file(format("%s/policies/node-policy.json", path.module))}"

  vars {
    name        = "${var.name}"
    arn_region  = "${var.arn_region}"
  }
}

data "template_file" "node_system_proxy" {
  template = "${file(format("%s/environment/system_proxy.config", path.module))}"
  vars {
    http_proxy  = "${var.http_proxy}"
    https_proxy = "${var.https_proxy}"
    no_proxy    = "${var.no_proxy}"
  }
}

data "template_file" "node_docker_proxy" {
  template = "${file(format("%s/environment/docker_proxy.config", path.module))}"
  vars {
    http_proxy  = "${var.http_proxy}"
    https_proxy = "${var.https_proxy}"
    no_proxy    = "${var.no_proxy}"
  }
}

data "template_file" "node_user_proxy" {
  template = "${file(format("%s/environment/user_proxy.config", path.module))}"
  vars {
    http_proxy  = "${var.http_proxy}"
    https_proxy = "${var.https_proxy}"
    no_proxy    = "${var.no_proxy}"
  }
}

data "template_file" "node" {
  template = "${file(format("%s/cloud-configs/node.yaml", path.module))}"

  vars {
    kubernetes_api_dns_name         = "${aws_elb.kubernetes_api.dns_name}"
    kubernetes_dns_service_ip       = "${var.kubernetes_dns_service_ip}"
    kubernetes_hyperkube_image_repo = "${var.kubernetes_hyperkube_image_repo}"
    kubernetes_version              = "${var.kubernetes_version}"
    system_proxy                    = "${var.http_proxy != "" || var.https_proxy != "" || var.no_proxy != "" ? data.template_file.node_system_proxy.rendered : ""}"
    docker_proxy                    = "${var.http_proxy != "" || var.https_proxy != "" || var.no_proxy != "" ? data.template_file.node_docker_proxy.rendered : ""}"
    user_proxy                      = "${var.http_proxy != "" || var.https_proxy != "" || var.no_proxy != "" ? data.template_file.node_user_proxy.rendered : ""}"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

