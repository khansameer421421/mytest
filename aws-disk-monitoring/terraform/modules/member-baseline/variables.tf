variable "controller_role_arn" {
  description = "ARN of the Ansible controller role in the monitoring account."
  type        = string
}

variable "organization_id" {
  description = "Organization ID required of the caller. Set to null for an acquired account that is not in the organization yet."
  type        = string
  default     = null
}

variable "member_role_name" {
  type    = string
  default = "DiskMonitorAnsibleRole"
}

variable "artifact_bucket_name" {
  description = "Bucket created by the monitoring-central module."
  type        = string
}

variable "central_event_bus_arn" {
  description = "ARN of the central disk-monitoring event bus."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
