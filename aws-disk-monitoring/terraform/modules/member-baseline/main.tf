# Global IAM baseline for one member account (IAM is global, so apply once
# per account): the role the Ansible controller assumes, the VM instance
# profile, and the role EventBridge uses to forward alarm events.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
}

# --------------------------------------------------- role for the controller --
# Least privilege: discover instances, open Session Manager shells on them,
# manage DiskMon-* alarms. Nothing else.

data "aws_iam_policy_document" "ansible_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [var.controller_role_arn]
    }
    dynamic "condition" {
      for_each = var.organization_id == null ? [] : [1]
      content {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = [var.organization_id]
      }
    }
  }
}

data "aws_iam_policy_document" "ansible" {
  statement {
    sid = "Discover"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeTags",
      "ssm:DescribeInstanceInformation",
      "ssm:GetConnectionStatus",
      "ssm:DescribeSessions",
      "cloudwatch:DescribeAlarms",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "StartSessionOnOptedInInstances"
    actions   = ["ssm:StartSession"]
    resources = ["arn:${local.partition}:ec2:*:${local.account_id}:instance/*"]
    condition {
      test     = "StringNotEquals"
      variable = "ssm:resourceTag/DiskMonitoring"
      values   = ["disabled"]
    }
  }

  statement {
    sid       = "StartSessionDefaultShellDocumentOnly"
    actions   = ["ssm:StartSession"]
    resources = ["arn:${local.partition}:ssm:*:${local.account_id}:document/SSM-SessionManagerRunShell"]
  }

  statement {
    sid       = "ManageOwnSessions"
    actions   = ["ssm:TerminateSession", "ssm:ResumeSession"]
    resources = ["arn:${local.partition}:ssm:*:*:session/$${aws:userid}-*"]
  }

  statement {
    sid       = "SsmTransferBucket"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["arn:${local.partition}:s3:::${var.artifact_bucket_name}/ansible-ssm/*"]
  }

  statement {
    sid       = "SsmTransferBucketLookup"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::${var.artifact_bucket_name}"]
  }

  statement {
    sid       = "ManageDiskAlarmsOnly"
    actions   = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms"]
    resources = ["arn:${local.partition}:cloudwatch:*:${local.account_id}:alarm:DiskMon-*"]
  }
}

resource "aws_iam_role" "ansible" {
  name                 = var.member_role_name
  assume_role_policy   = data.aws_iam_policy_document.ansible_trust.json
  max_session_duration = 3600
  tags                 = var.tags
}

resource "aws_iam_role_policy" "ansible" {
  name   = "disk-monitoring-ansible"
  role   = aws_iam_role.ansible.id
  policy = data.aws_iam_policy_document.ansible.json
}

# ------------------------------------------------------ VM instance profile --
# SSM agent + CloudWatch agent. Attach to launch templates; instances without
# a profile show up in the no_instance_profile inventory group.

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "DiskMonitorInstanceRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "instance" {
  for_each = toset([
    "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:${local.partition}:iam::aws:policy/CloudWatchAgentServerPolicy",
  ])
  role       = aws_iam_role.instance.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "instance" {
  name = "DiskMonitorInstanceRole"
  role = aws_iam_role.instance.name
  tags = var.tags
}

# ------------------------------------------- EventBridge forwarding role --

data "aws_iam_policy_document" "events_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "events_forward" {
  statement {
    actions   = ["events:PutEvents"]
    resources = [var.central_event_bus_arn]
  }
}

resource "aws_iam_role" "events_forward" {
  name               = "DiskMonitorEventForwardRole"
  assume_role_policy = data.aws_iam_policy_document.events_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "events_forward" {
  name   = "put-central-bus"
  role   = aws_iam_role.events_forward.id
  policy = data.aws_iam_policy_document.events_forward.json
}
