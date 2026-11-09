# Central resources in the monitoring (tooling) account, home region:
# Ansible controller identity, SSM transfer / report bucket, central alert
# bus and SNS topic.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id              = data.aws_caller_identity.current.account_id
  region                  = data.aws_region.current.region
  partition               = data.aws_partition.current.partition
  bucket_name             = "disk-monitoring-${local.account_id}-${local.region}"
  member_role_arn_pattern = "arn:${local.partition}:iam::*:role/${var.member_role_name}"
}

# ------------------------------------------------------------------ bucket --

resource "aws_s3_bucket" "artifacts" {
  bucket        = local.bucket_name
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-ssm-transfer"
    status = "Enabled"
    filter {
      prefix = "ansible-ssm/"
    }
    expiration {
      days = 1
    }
  }

  rule {
    id     = "expire-old-reports"
    status = "Enabled"
    filter {
      prefix = "reports/"
    }
    expiration {
      days = var.report_retention_days
    }
  }
}

data "aws_iam_policy_document" "artifacts" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # The aws_ssm connection plugin, running as the member-account role,
  # stages module files here and hands the VM a pre-signed URL.
  statement {
    sid       = "AllowMemberRolesSsmTransfer"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/ansible-ssm/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = [local.member_role_arn_pattern]
    }
  }

  statement {
    sid       = "AllowMemberRolesBucketLookup"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = [local.member_role_arn_pattern]
    }
  }

  # Acquired accounts not yet in the organization (see docs/DESIGN.md).
  dynamic "statement" {
    for_each = length(var.external_member_account_ids) > 0 ? [1] : []
    content {
      sid       = "AllowExternalMemberRolesSsmTransfer"
      actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
      resources = ["${aws_s3_bucket.artifacts.arn}/ansible-ssm/*"]
      principals {
        type        = "AWS"
        identifiers = [for id in var.external_member_account_ids : "arn:${local.partition}:iam::${id}:role/${var.member_role_name}"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifacts.json

  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

# -------------------------------------------------------------- controller --

data "aws_iam_policy_document" "controller_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "controller" {
  name               = var.controller_role_name
  description        = "Identity of the Ansible controller (EC2 / AWX). No long-lived keys."
  assume_role_policy = data.aws_iam_policy_document.controller_trust.json
  tags               = var.tags
}

# Operators reach the controller itself through Session Manager too.
resource "aws_iam_role_policy_attachment" "controller_ssm" {
  role       = aws_iam_role.controller.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "controller" {
  statement {
    sid       = "AssumeMemberRoleInsideOrgOnly"
    actions   = ["sts:AssumeRole"]
    resources = [local.member_role_arn_pattern]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceOrgID"
      values   = [var.organization_id]
    }
  }

  dynamic "statement" {
    for_each = length(var.external_member_account_ids) > 0 ? [1] : []
    content {
      sid       = "AssumeExternalMemberRoles"
      actions   = ["sts:AssumeRole"]
      resources = [for id in var.external_member_account_ids : "arn:${local.partition}:iam::${id}:role/${var.member_role_name}"]
    }
  }

  statement {
    sid       = "DiscoverAccounts"
    actions   = ["organizations:ListAccounts", "organizations:DescribeAccount"]
    resources = ["*"]
  }

  statement {
    sid       = "PublishReports"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/reports/*"]
  }

  statement {
    sid       = "SendDigest"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid       = "ManageDashboard"
    actions   = ["cloudwatch:PutDashboard", "cloudwatch:GetDashboard"]
    resources = ["arn:${local.partition}:cloudwatch::${local.account_id}:dashboard/DiskUtilisation"]
  }
}

resource "aws_iam_role_policy" "controller" {
  name   = "disk-monitoring-controller"
  role   = aws_iam_role.controller.id
  policy = data.aws_iam_policy_document.controller.json
}

resource "aws_iam_instance_profile" "controller" {
  name = var.controller_role_name
  role = aws_iam_role.controller.name
  tags = var.tags
}

# ------------------------------------------------------------------ alerts --

resource "aws_sns_topic" "alerts" {
  name              = "disk-monitoring-alerts"
  kms_master_key_id = "alias/aws/sns"
  tags              = var.tags
}

data "aws_iam_policy_document" "alerts" {
  statement {
    sid       = "AllowEventBridge"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
  statement {
    sid       = "AllowController"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.controller.arn]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# Alarm state changes from every member account/region land here.
resource "aws_cloudwatch_event_bus" "central" {
  name = "disk-monitoring"
  tags = var.tags
}

data "aws_iam_policy_document" "central_bus" {
  statement {
    sid       = "AllowOrgPutEvents"
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.central.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}

resource "aws_cloudwatch_event_bus_policy" "central" {
  event_bus_name = aws_cloudwatch_event_bus.central.name
  policy         = data.aws_iam_policy_document.central_bus.json
}

resource "aws_cloudwatch_event_rule" "alarm_to_sns" {
  name           = "disk-alarm-state-to-sns"
  event_bus_name = aws_cloudwatch_event_bus.central.name
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [{ prefix = "DiskMon-" }]
      state     = { value = ["ALARM", "OK"] }
    }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "alarm_to_sns" {
  rule           = aws_cloudwatch_event_rule.alarm_to_sns.name
  event_bus_name = aws_cloudwatch_event_bus.central.name
  target_id      = "sns"
  arn            = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      alarm   = "$.detail.alarmName"
      state   = "$.detail.state.value"
      reason  = "$.detail.state.reason"
      account = "$.account"
      region  = "$.region"
    }
    input_template = "\"[<state>] <alarm> - account <account> / <region>: <reason>\""
  }
}
