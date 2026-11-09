# CloudWatch cross-account observability sink in the monitoring account.
# OAM links are regional, so instantiate this module once per monitored
# region (one provider alias per region in live/monitoring).

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

variable "organization_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_oam_sink" "this" {
  name = "disk-monitoring-sink"
  tags = var.tags
}

data "aws_iam_policy_document" "sink" {
  statement {
    actions   = ["oam:CreateLink", "oam:UpdateLink"]
    resources = ["*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
    # Share metrics only - no logs or traces leave member accounts.
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "oam:ResourceTypes"
      values   = ["AWS::CloudWatch::Metric"]
    }
  }
}

resource "aws_oam_sink_policy" "this" {
  sink_identifier = aws_oam_sink.this.arn
  policy          = data.aws_iam_policy_document.sink.json
}

output "sink_arn" {
  value = aws_oam_sink.this.arn
}
