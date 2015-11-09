//Provider
provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "us-east-1"
}

// Artifacts
resource "atlas_artifact" "mongodb" {
  name = "${var.atlas_username}/mongodb"
  type = "aws.ami"

  lifecycle { create_before_destroy = true }
}

resource "atlas_artifact" "nodejs" {
  name = "${var.atlas_username}/nodejs"
  type = "aws.ami"

  lifecycle { create_before_destroy = true }
}

resource "atlas_artifact" "consul" {
  name = "${var.atlas_username}/consul"
  type = "aws.ami"

  lifecycle { create_before_destroy = true }
}

resource "atlas_artifact" "haproxy" {
  name = "${var.atlas_username}/haproxy"
  type = "aws.ami"
}

// TEMPLATES
resource "template_file" "consul_upstart" {
  filename = "files/consul.sh"

  vars {
    atlas_user_token = "${var.atlas_user_token}"
    atlas_username = "${var.atlas_username}"
    atlas_environment = "${var.atlas_environment}"
    consul_server_count = "${var.consul_server_count}"
    }
}

// SSH Keys
module "ssh_keys" {
  source = "./ssh_keys"

  name = "${var.key_name}"
}

//Networking
resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags { Name = "${var.name}" }
  lifecycle { create_before_destroy = true }
}

resource "aws_internet_gateway" "public" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags { Name = "${var.name}" }
  lifecycle { create_before_destroy = true }
}

resource "aws_subnet" "public" {
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${var.subnet_cidr}"

  tags { Name = "${var.name}" }
  lifecycle { create_before_destroy = true }

  map_public_ip_on_launch = true
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = "${aws_internet_gateway.public.id}"
  }
  tags { Name = "${var.name}" }
  lifecycle { create_before_destroy = true }
}

resource "aws_route_table_association" "public" {
  subnet_id      = "${aws_subnet.public.id}"
  route_table_id = "${aws_route_table.public.id}"

  lifecycle { create_before_destroy = true }
}

//MongoDB Security Group
resource "aws_security_group" "mongodb" {
  name        = "mongodb"
  vpc_id      = "${aws_vpc.vpc.id}"
  description = "Allow all inbound traffic from VPC and SSH from world"

  tags { Name = "${var.name}-mongodb" }
  lifecycle { create_before_destroy = true }

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//MongoDB Instance
resource "aws_instance" "mongodb" {
  ami           = "${atlas_artifact.mongodb.metadata_full.region-us-east-1}"
  user_data       = "${template_file.consul_upstart.rendered}"
  instance_type = "t2.micro"
  key_name      = "${module.ssh_keys.key_name}"
  subnet_id     = "${aws_subnet.public.id}"

  vpc_security_group_ids = ["${aws_security_group.mongodb.id}"]

  tags { Name = "${var.name}-mongodb" }
  lifecycle { create_before_destroy = true }
}

//Node.js Security Group
resource "aws_security_group" "nodejs" {
  name        = "nodejs"
  vpc_id      = "${aws_vpc.vpc.id}"
  description = "Allow all inbound traffic from VPC and SSH from world"

  tags { Name = "${var.name}-nodejs" }
  lifecycle { create_before_destroy = true }

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    protocol    = "tcp"
    from_port   = 5000
    to_port     = 5000
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//Node.js Instance
resource "aws_instance" "nodejs" {
  ami             = "${atlas_artifact.nodejs.metadata_full.region-us-east-1}"
  user_data       = "${template_file.consul_upstart.rendered}"
  instance_type   = "t2.micro"
  key_name        = "${module.ssh_keys.key_name}"
  subnet_id       = "${aws_subnet.public.id}"

  vpc_security_group_ids = ["${aws_security_group.nodejs.id}"]

  tags { Name = "${var.name}-nodejs" }
  lifecycle { create_before_destroy = true }
  depends_on = ["aws_instance.mongodb"]
  count      = 2
}

//Consul Security Group
resource "aws_security_group" "consul" {
  name        = "consul"
  vpc_id      = "${aws_vpc.vpc.id}"
  description = "Allow all inbound traffic from VPC and SSH from world"

  tags { Name = "${var.name}-consul" }
  lifecycle { create_before_destroy = true }

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["${var.vpc_cidr}"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//Consul Instance
resource "aws_instance" "consul" {
  ami             = "${atlas_artifact.consul.metadata_full.region-us-east-1}"
  user_data       = "${template_file.consul_upstart.rendered}"
  instance_type   = "t2.micro"
  key_name        = "${module.ssh_keys.key_name}"
  subnet_id       = "${aws_subnet.public.id}"
  
  vpc_security_group_ids = ["${aws_security_group.consul.id}"]

  tags { Name = "${var.name}-consul" }
  lifecycle { create_before_destroy = true }
  
  count		  = "3"
}

//HAPROXY Security Group
resource "aws_security_group" "haproxy" {
  name   = "haproxy"
  vpc_id = "${aws_vpc.vpc.id}"

  tags { Name = "${var.name}-haproxy" }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // allow traffic for SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  // connect to scada
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

//HAPROXY Instance
resource "aws_instance" "haproxy" {
  ami             = "${atlas_artifact.haproxy.metadata_full.region-us-east-1}"
  user_data       = "${template_file.consul_upstart.rendered}"
  instance_type   = "t2.micro"
  key_name        = "${module.ssh_keys.key_name}"
  subnet_id       = "${aws_subnet.public.id}"

  vpc_security_group_ids = ["${aws_security_group.haproxy.id}"]

  tags { Name = "${var.name}-haproxy" }
  lifecycle { create_before_destroy = true }

  count           = "1"
}

output "letschat_address" {
  value = "http://${aws_instance.haproxy.public_ip}"
}