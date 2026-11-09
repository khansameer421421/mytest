# Per-region baseline for one member account: share metrics with the
# monitoring account, forward DiskMon-* alarm events to the central bus, and
# a fleet-wide backstop alarm. Instantiate once per monitored region.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

variable "sink_arn" {
  description = "OAM sink ARN in the monitoring account for THIS region."
  type        = string
}

variable "central_event_bus_arn" {
  type = string
}

variable "events_forward_role_arn" {
  type = string
}

variable "backstop_threshold" {
  description = "Fleet backstop alarm fires when any filesystem is at or above this % used."
  type        = number
  default     = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_oam_link" "metrics" {
  label_template  = "$AccountName"
  resource_types  = ["AWS::CloudWatch::Metric"]
  sink_identifier = var.sink_arn
  tags            = var.tags
}

resource "aws_cloudwatch_event_rule" "forward_alarms" {
  name = "disk-alarm-state-forward"
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      alarmName = [{ prefix = "DiskMon-" }]
    }
  })
  tags = var.tags
}

resource "aws_cloudwatch_event_target" "forward_alarms" {
  rule      = aws_cloudwatch_event_rule.forward_alarms.name
  target_id = "central-bus"
  arn       = var.central_event_bus_arn
  role_arn  = var.events_forward_role_arn
}

# One alarm per account/region over EVERY filesystem reporting to CloudWatch
# (Metrics Insights query). Covers VMs launched between Ansible runs, before
# their per-filesystem alarms exist.
resource "aws_cloudwatch_metric_alarm" "fleet_backstop" {
  alarm_name          = "DiskMon-fleet-backstop"
  alarm_description   = "Some filesystem in ${data.aws_caller_identity.current.account_id}/${data.aws_region.current.region} is above ${var.backstop_threshold}% used. See the DiskUtilisation dashboard."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.backstop_threshold
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "fleetmax"
    expression  = "SELECT MAX(disk_used_percent) FROM SCHEMA(CWAgent, InstanceId, fstype, path)"
    period      = 300
    return_data = true
  }

  tags = var.tags
}
