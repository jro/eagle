provider "aws" {
  region     = "${var.aws_region}"
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# we're going lazy-mode and just using 1 subnet for now
resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_key_pair" "auth" {
  key_name   = "admin"
  public_key = "${file("ssh/sshkey.pub")}"
}

resource "aws_security_group" "buildkite" {
  name        = "Buildkite servers"
  vpc_id      = "${aws_vpc.default.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "buildkite_iam_role" {
  name = "buildkite_iam_role"
  lifecycle { ignore_changes = ["aws_iam_role"] }
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "autoscaling.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "buildkite_iam_profile" {
    name = "buildkite_iam_profile"
    roles = ["${aws_iam_role.buildkite_iam_role.name}"]
}

resource "aws_iam_role_policy" "buildkite_autoscaling_policy" {
  name = "buildkite_autoscaling_policy"
  role = "${aws_iam_role.buildkite_iam_role.id}"
  policy = <<EOF
{
  "Statement": [{
      "Effect": "Allow",
      "Action" : [
        "autoscaling:*"
      ],
      "Resource" : "*"
  }]
}
EOF
}

resource "aws_iam_role_policy" "buildkite_elb_policy" {
  name = "buildkite_elb_policy"
  role = "${aws_iam_role.buildkite_iam_role.id}"
  policy = <<EOF
{
  "Statement": [{
      "Effect": "Allow",
      "Action" : [
        "elasticloadbalancing:*"
      ],
      "Resource" : "*"
  }]
}
EOF
}

resource "aws_iam_role_policy" "buildkite_ec2_policy" {
  name = "buildkite_ec2_policy"
  role = "${aws_iam_role.buildkite_iam_role.id}"
  policy = <<EOF
{
  "Statement": [{
      "Effect": "Allow",
      "Action" : [
        "ec2:*"
      ],
      "Resource" : "*"
  }]
}
EOF
}

resource "aws_iam_role_policy" "buildkite_s3_policy" {
  name = "buildkite_s3_policy"
  role = "${aws_iam_role.buildkite_iam_role.id}"
  policy = <<EOF
{
  "Statement": [{
      "Effect": "Allow",
      "Action" : [
        "s3:*"
      ],
      "Resource" : "*"
  }]
}
EOF
}

resource "aws_iam_role_policy" "buildkite_cloudformation_policy" {
  name = "buildkite_cloudformation_policy"
  role = "${aws_iam_role.buildkite_iam_role.id}"
  policy = <<EOF
{
    "Statement":[{
        "Effect":"Allow",
        "Action":[
            "cloudformation:*"
        ],
        "Resource":"*"
    }]
}
EOF
}

data "aws_ami" "buildkite" {
  most_recent = true
  filter {
    name = "name"
    values = ["buildkite"]
  }
  owners = ["self"]
}

resource "aws_instance" "buildkite" {
  ami           = "${data.aws_ami.buildkite.id}"
  instance_type = "t2.micro"

  vpc_security_group_ids = ["${aws_security_group.buildkite.id}"]
  subnet_id = "${aws_subnet.default.id}"

  key_name = "${aws_key_pair.auth.id}"
  iam_instance_profile = "${aws_iam_instance_profile.buildkite_iam_profile.id}"
  # user_data = "${file("userdata/buildkite.sh")}"
}
