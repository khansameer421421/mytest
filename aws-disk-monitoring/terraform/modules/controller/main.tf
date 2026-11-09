# Ansible controller: a small EC2 instance in a private subnet with no
# inbound access at all (operators use Session Manager). A systemd timer runs
# inventory generation + site.yml every hour.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

variable "subnet_id" {
  description = "Private subnet with a route to SSM/STS/EC2/S3 (NAT or VPC endpoints)."
  type        = string
}

variable "instance_profile_name" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "repo_url" {
  description = "Git URL of this repository, cloned onto the controller."
  type        = string
}

variable "repo_subdir" {
  description = "Directory inside the repository that holds ansible.cfg."
  type        = string
  default     = "aws-disk-monitoring"
}

variable "schedule" {
  description = "systemd OnCalendar expression for the monitoring run."
  type        = string
  default     = "hourly"
}

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_subnet" "this" {
  id = var.subnet_id
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_security_group" "controller" {
  name        = "disk-monitoring-controller"
  description = "Ansible controller - no inbound, HTTPS out only"
  vpc_id      = data.aws_subnet.this.vpc_id
  tags        = var.tags

  egress {
    description = "HTTPS to AWS APIs, SSM and package repositories"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "controller" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = var.instance_profile_name
  vpc_security_group_ids = [aws_security_group.controller.id]

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url    = var.repo_url
    repo_subdir = var.repo_subdir
    schedule    = var.schedule
  })
  user_data_replace_on_change = true

  tags = merge(var.tags, { Name = "disk-monitoring-controller" })

  lifecycle {
    ignore_changes = [ami]
  }
}

output "instance_id" {
  value = aws_instance.controller.id
}
