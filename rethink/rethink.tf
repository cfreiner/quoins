/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "subnet_ids" {
  description = "A comma-separated list of subnet ids to use for the instances."
}

variable "rethink_elb_cert" {
  description = "The public certificate to be used by the ELB that fronts rethink instances encoded in PEM format."
}

variable "rethink_elb_key" {
  description = "The private key to be used by the ELB that fronts rethink instances encode in PEM format."
}

variable "rethink_cluster_cert" {
  description = "The public certificate to be used by rethink servers for peer connections encoded in base64 format."
}

variable "rethink_cluster_key" {
  description = "The private key to be used by rethink servers for peer connections encoded in base64 format."
}

variable "rethink_driver_cert" {
  description = "The public certificate to be used by rethink servers for driver connections encoded in base64 format."
}

variable "rethink_driver_key" {
  description = "The private key to be used by rethink servers for driver connections encoded in base64 format."
}

variable "rethink_driver_cert_plain" {
  description = "The public certificate to be used by ELB backend authentication for driver connections encoded in pem format."
}

variable "rethink_min_size" {
  description = "The minimum size for the rethink cluster. NOTE: Use odd numbers."
  default     = "1"
}

variable "rethink_max_size" {
  description = "The maximum size for the rethink cluster. NOTE: Use odd numbers."
  default     = "9"
}

variable "rethink_desired_capacity" {
  description = "The desired capacity of the rethink cluster. NOTE: Use odd numbers."
  default     = "1"
}

variable "rethink_root_volume_size" {
  description = "Set the desired capacity for the root volume in GB."
  default     = "12"
}

variable "rethink_docker_volume_size" {
  description = "Set the desired capacity for the docker volume in GB."
  default     = "12"
}

variable "rethink_data_volume_size" {
  description = "Set the desired capacity for the rethink data volume in GB."
  default     = "12"
}

variable "rethink_instance_type" {
  description = "The type of instance to use for the rethink cluster. Example: 'm3.medium'"
  default     = "m3.medium"
}

variable "key_name" {
  description = "A name for the given key pair to use for instances."
}

variable "bastion_security_group_id" {
  description = "Security Group ID for bastion instance with external SSH allows ssh connections on port 22"
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Auto Scaling Group and Launch Configuration
resource "aws_autoscaling_group" "rethink" {
  name                 = "${format("%s", var.name)}"
  min_size             = "${var.rethink_min_size}"
  max_size             = "${var.rethink_max_size}"
  desired_capacity     = "${var.rethink_desired_capacity}"
  availability_zones   = ["${split(",", var.availability_zones)}"]
  vpc_zone_identifier  = ["${split(",", var.subnet_ids)}"]
  health_check_type    = "EC2"
  force_delete         = true
  load_balancers       = ["${aws_elb.rethink.id}"]
  launch_configuration = "${aws_launch_configuration.rethink.name}"

  tag {
    key                 = "Name"
    value               = "${format("%s", var.name)}"
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
}

resource "aws_launch_configuration" "rethink" {
  name_prefix          = "${format("%s-", var.name)}"
  image_id             = "${data.aws_ami.coreos_ami.id}"
  instance_type        = "${var.rethink_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.rethink.name}"
  security_groups      = ["${aws_security_group.rethink.id}"]
  key_name             = "${var.key_name}"
  depends_on           = ["aws_s3_bucket.cluster", "aws_s3_bucket_object.rethink", "aws_iam_instance_profile.rethink", "aws_security_group.rethink"]

  # /root
  root_block_device = {
    volume_type = "gp2"
    volume_size = "${var.rethink_root_volume_size}"
  }

  # /var/lib/docker
  ebs_block_device = {
    device_name = "/dev/sdf"
    encrypted   = true
    volume_type = "gp2"
    volume_size = "${var.rethink_docker_volume_size}"
  }

  # /opt/rethink
  ebs_block_device = {
    device_name = "/dev/sdg"
    encrypted   = true
    volume_type = "gp2"
    volume_size = "${var.rethink_data_volume_size}"
  }

  user_data = "${data.template_file.s3_cloudconfig_bootstrap.rendered}"
}

# Elastic Load Balancer
resource "aws_elb" "rethink" {
  name                = "${format("%s", var.name)}"
  connection_draining = true
  internal            = true
  security_groups     = ["${aws_security_group.balancers.id}"]
  subnets             = ["${split(",", var.subnet_ids)}"]

  listener {
    instance_port     = 28015
    instance_protocol = "ssl"
    lb_port           = 28015
    lb_protocol       = "ssl"
    ssl_certificate_id = "${aws_iam_server_certificate.rethink_elb_certificate.arn}"
  }

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 3
    target              = "ssl:28015"
    interval            = 60
  }

  tags {
    Name = "${format("%s", var.name)}"
  }
}

resource "aws_security_group" "balancers" {
  name   = "${format("%s-balancers-%s", var.name, element(split("-", var.vpc_id), 1))}"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port   = 28015
    to_port     = 28015
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${format("%s-balancers", var.name)}"
  }
}

resource "aws_load_balancer_policy" "rethink_public_key_policy" {
  load_balancer_name = "${aws_elb.rethink.name}"
  policy_name        = "${format("%s-public-key-policy", var.name)}"
  policy_type_name   = "PublicKeyPolicyType"

  policy_attribute = {
    name  = "PublicKey"
    value = "${var.rethink_driver_cert_plain}"
  }
}

resource "aws_load_balancer_policy" "rethink_backend_auth_policy" {
  load_balancer_name = "${aws_elb.rethink.name}"
  policy_name        = "${format("%s-backend-auth-policy", var.name)}"
  policy_type_name   = "BackendServerAuthenticationPolicyType"

  policy_attribute = {
    name  = "PublicKeyPolicyName"
    value = "${aws_load_balancer_policy.rethink_public_key_policy.policy_name}"
  }
}

resource "aws_load_balancer_backend_server_policy" "rethink_auth_policies_28015" {
  load_balancer_name = "${aws_elb.rethink.name}"
  instance_port      = 28015

  policy_names = [
    "${aws_load_balancer_policy.rethink_backend_auth_policy.policy_name}",
  ]
}

resource "aws_iam_server_certificate" "rethink_elb_certificate" {
  name             = "${format("%s-elb-cert", var.name)}"
  certificate_body = "${var.rethink_elb_cert}"
  private_key      = "${var.rethink_elb_key}"
}

# Security Group
resource "aws_security_group" "rethink" {
  name       = "${format("%s-%s", var.name, element(split("-", var.vpc_id), 1))}"
  vpc_id     = "${var.vpc_id}"

  # Allow SSH from the bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${var.bastion_security_group_id}"]
  }

  # Allow rethink peers to communicate, include rethink proxies
  ingress {
    from_port   = 29015
    to_port     = 29015
    protocol    = "tcp"
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  # Allow rethink client to communicate
  ingress {
    from_port   = 28015
    to_port     = 28015
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${format("%s", var.name)}"
  }
}

# rethink cloud-config
resource "aws_s3_bucket_object" "rethink" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/rethink/cloud-config.yaml"
  content = "${data.template_file.rethink.rendered}"
}

# Certificates
resource "aws_s3_bucket_object" "rethink_cluster_cert" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/rethink/tls/rethink-cluster.pem.enc.base"
  content = "${var.rethink_cluster_cert}"
}

resource "aws_s3_bucket_object" "rethink_cluster_key" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/rethink/tls/rethink-cluster-key.pem.enc.base"
  content = "${var.rethink_cluster_key}"
}

resource "aws_s3_bucket_object" "rethink_driver_cert" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/rethink/tls/rethink-driver.pem.enc.base"
  content = "${var.rethink_driver_cert}"
}

resource "aws_s3_bucket_object" "rethink_driver_key" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/rethink/tls/rethink-driver-key.pem.enc.base"
  content = "${var.rethink_driver_key}"
}

# Profile, Role, and Policy
resource "aws_iam_instance_profile" "rethink" {
  name       = "${format("%s", var.name)}"
  roles      = ["${aws_iam_role.rethink.name}"]
  depends_on = ["aws_iam_role.rethink", "aws_iam_role_policy.rethink_policy"]
}

resource "aws_iam_role_policy" "rethink_policy" {
  name       = "${format("%s-policy", var.name)}"
  role       = "${aws_iam_role.rethink.id}"
  policy     = "${data.template_file.rethink_policy.rendered}"
  depends_on = ["aws_iam_role.rethink", "data.template_file.rethink_policy"]
}

resource "aws_iam_role" "rethink" {
  name               = "${format("%s", var.name)}"
  path               = "/"
  assume_role_policy = "${file(format("%s/policies/assume-role-policy.json", path.module))}"
}

/*
* ------------------------------------------------------------------------------
* Data Sources
* ------------------------------------------------------------------------------
*/

# Templates
data "template_file" "rethink_policy" {
  template = "${file(format("%s/policies/rethink-policy.json", path.module))}"

  vars {
    name        = "${var.name}"
    kms_key_arn = "${var.kms_key_arn}"
  }
}

data "template_file" "rethink" {
  template = "${file(format("%s/cloud-configs/rethink.yaml", path.module))}"
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# The ELB DNS in which you can access Vault.
output "rethink_dns" {
  value = "${aws_elb.rethink.dns_name}"
}