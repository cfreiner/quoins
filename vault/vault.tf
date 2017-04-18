/*
* ------------------------------------------------------------------------------
* Variables
* ------------------------------------------------------------------------------
*/

variable "subnet_ids" {
  description = "A comma-separated list of subnet ids to use for the instances."
}

variable "vault_elb_cert" {
  description = "The public certificate to be used by the ELB that fronts vault instances encoded in PEM format."
}

variable "vault_elb_key" {
  description = "The private key to be used by the ELB that fronts vault instances encode in PEM format."
}

variable "vault_server_cert_plain" {
  description = "The public certificate to be used by vault servers encoded in PEM format."
}

variable "vault_server_cert" {
  description = "The public certificate to be used by vault servers encoded in base64 format."
}

variable "vault_server_key" {
  description = "The private key to be used by vault servers encoded in base64 format."
}

variable "vault_etcd_client_cert" {
  description = "The public client certificate to be used for authenticating against etcd encoded in base64 format."
}

variable "vault_etcd_client_key" {
  description = "The client private key to be used for authenticating against etcd encoded in base64 format."
}

variable "vault_min_size" {
  description = "The minimum size for the vault cluster. NOTE: Use odd numbers."
  default     = "1"
}

variable "vault_max_size" {
  description = "The maximum size for the vault cluster. NOTE: Use odd numbers."
  default     = "3"
}

variable "vault_desired_capacity" {
  description = "The desired capacity of the vault cluster. NOTE: Use odd numbers."
  default     = "1"
}

variable "vault_root_volume_size" {
  description = "Set the desired capacity for the root volume in GB."
  default     = "12"
}

variable "vault_docker_volume_size" {
  description = "Set the desired capacity for the docker volume in GB."
  default     = "12"
}

variable "vault_instance_type" {
  description = "The type of instance to use for the vault cluster. Example: 'm3.medium'"
  default     = "m3.medium"
}

variable "key_name" {
  description = "A name for the given key pair to use for instances."
}

variable "etcd_cluster_quoin_name" {
  description = "A name for a running etcd cluster used by vault."
}

/*
* ------------------------------------------------------------------------------
* Resources
* ------------------------------------------------------------------------------
*/

# Auto Scaling Group and Launch Configuration
resource "aws_autoscaling_group" "vault" {
  name                 = "${format("%s", var.name)}"
  min_size             = "${var.vault_min_size}"
  max_size             = "${var.vault_max_size}"
  desired_capacity     = "${var.vault_desired_capacity}"
  availability_zones   = ["${split(",", var.availability_zones)}"]
  vpc_zone_identifier  = ["${split(",", var.subnet_ids)}"]
  health_check_type    = "EC2"
  force_delete         = true
  load_balancers       = ["${aws_elb.vault.id}"]
  launch_configuration = "${aws_launch_configuration.vault.name}"

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

resource "aws_launch_configuration" "vault" {
  name_prefix          = "${format("%s-", var.name)}"
  image_id             = "${data.aws_ami.coreos_ami.id}"
  instance_type        = "${var.vault_instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.vault.name}"
  security_groups      = ["${aws_security_group.vault.id}"]
  key_name             = "${var.key_name}"
  depends_on           = ["aws_s3_bucket.cluster", "aws_s3_bucket_object.vault", "aws_iam_instance_profile.vault", "aws_security_group.vault"]

  # /root
  root_block_device = {
    volume_type = "gp2"
    volume_size = "${var.vault_root_volume_size}"
  }

  # /var/lib/docker
  ebs_block_device = {
    device_name = "/dev/sdf"
    encrypted   = true
    volume_type = "gp2"
    volume_size = "${var.vault_docker_volume_size}"
  }

  user_data = "${data.template_file.s3_cloudconfig_bootstrap.rendered}"
}

# Security Group
resource "aws_security_group" "vault" {
  name       = "${format("%s-%s", var.name, element(split("-", var.vpc_id), 1))}"
  vpc_id     = "${var.vpc_id}"
  depends_on = ["aws_security_group.bastion"]

  # Allow SSH from the bastion
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${aws_security_group.bastion.id}"]
  }

  # Allow vault clients to communicate
  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  # Allow vault peers to communicate
  ingress {
    from_port   = 8201
    to_port     = 8201
    protocol    = "tcp"
    cidr_blocks = ["${var.vpc_cidr}"]
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

# Load Balancer
resource "aws_elb" "vault" {
  name                = "${format("%s", var.name)}"
  connection_draining = true
  internal            = true
  security_groups     = ["${aws_security_group.balancers.id}"]
  subnets             = ["${split(",", var.subnet_ids)}"]

  listener {
    instance_port     = 8200
    instance_protocol = "https"
    lb_port           = 443
    lb_protocol       = "https"
    ssl_certificate_id = "${aws_iam_server_certificate.vault_elb_certificate.arn}"
  }

  health_check {
    healthy_threshold   = 2
    interval            = 30
    target              = "https:8200/v1/sys/health"
    timeout             = 3
    unhealthy_threshold = 2
  }

  tags {
    Name = "${format("%s-elb", var.name)}"
  }
}

resource "aws_security_group" "balancers" {
  name   = "${format("%s-balancers-%s", var.name, element(split("-", var.vpc_id), 1))}"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${var.vpc_cidr}"]
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

resource "aws_load_balancer_policy" "vault_public_key_policy" {
  load_balancer_name = "${aws_elb.vault.name}"
  policy_name        = "${format("%s-public-key-policy", var.name)}"
  policy_type_name   = "PublicKeyPolicyType"

  policy_attribute = {
    name  = "PublicKey"
    value = "${var.vault_server_cert_plain}"
  }
}

resource "aws_load_balancer_policy" "vault_backend_auth_policy" {
  load_balancer_name = "${aws_elb.vault.name}"
  policy_name        = "${format("%s-backend-auth-policy", var.name)}"
  policy_type_name   = "BackendServerAuthenticationPolicyType"

  policy_attribute = {
    name  = "PublicKeyPolicyName"
    value = "${aws_load_balancer_policy.vault_public_key_policy.policy_name}"
  }
}

resource "aws_load_balancer_backend_server_policy" "vault_auth_policies_443" {
  load_balancer_name = "${aws_elb.vault.name}"
  instance_port      = 443

  policy_names = [
    "${aws_load_balancer_policy.vault_backend_auth_policy.policy_name}",
  ]
}

resource "aws_iam_server_certificate" "vault_elb_certificate" {
  name             = "${format("%s-elb-cert", var.name)}"
  certificate_body = "${var.vault_elb_cert}"
  private_key      = "${var.vault_elb_key}"
}

# Vault cloud-config
resource "aws_s3_bucket_object" "vault" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/vault/cloud-config.yaml"
  content = "${data.template_file.vault.rendered}"
}

# Certificates
resource "aws_s3_bucket_object" "vault_server_cert" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/vault/tls/vault-server.pem.enc.base"
  content = "${var.vault_server_cert}"
}

resource "aws_s3_bucket_object" "vault_server_key" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/vault/tls/vault-server-key.pem.enc.base"
  content = "${var.vault_server_key}"
}

resource "aws_s3_bucket_object" "vault_etcd_client_cert" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/common/tls/vault-etcd-client.pem.enc.base"
  content = "${var.vault_etcd_client_cert}"
}

resource "aws_s3_bucket_object" "vault_etcd_client_key" {
  bucket  = "${aws_s3_bucket.cluster.bucket}"
  key     = "cloudinit/common/tls/vault-etcd-client-key.pem.enc.base"
  content = "${var.vault_etcd_client_key}"
}

# Profile, Role, and Policy
resource "aws_iam_instance_profile" "vault" {
  name       = "${format("%s", var.name)}"
  roles      = ["${aws_iam_role.vault.name}"]
  depends_on = ["aws_iam_role.vault", "aws_iam_role_policy.vault_policy"]
}

resource "aws_iam_role_policy" "vault_policy" {
  name       = "${format("%s-policy", var.name)}"
  role       = "${aws_iam_role.vault.id}"
  policy     = "${data.template_file.vault_policy.rendered}"
  depends_on = ["aws_iam_role.vault", "data.template_file.vault_policy"]
}

resource "aws_iam_role" "vault" {
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
data "template_file" "vault_policy" {
  template = "${file(format("%s/policies/vault-policy.json", path.module))}"

  vars {
    name        = "${var.name}"
    kms_key_arn = "${var.kms_key_arn}"
  }
}

data "template_file" "vault" {
  template = "${file(format("%s/cloud-configs/vault.yaml", path.module))}"

  vars {
    etcd_cluster_quoin_name = "${var.etcd_cluster_quoin_name}"
  }
}

/*
* ------------------------------------------------------------------------------
* Outputs
* ------------------------------------------------------------------------------
*/

# The ELB DNS in which you can access the vault internally.
output "vault_dns" {
  value = "${aws_elb.vault.dns_name}"
}
