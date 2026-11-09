variable "organization_id" {
  description = "AWS Organizations ID (o-xxxxxxxxxx). Scopes every cross-account grant."
  type        = string
  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "organization_id must look like o-xxxxxxxxxx."
  }
}

variable "member_role_name" {
  description = "Name of the role the controller assumes in every member account."
  type        = string
  default     = "DiskMonitorAnsibleRole"
}

variable "controller_role_name" {
  description = "Name of the controller's IAM role and instance profile."
  type        = string
  default     = "DiskMonitorControllerRole"
}

variable "alert_emails" {
  description = "Initial e-mail subscribers for disk alerts (add Slack / PagerDuty / ITSM later)."
  type        = list(string)
  default     = []
}

variable "report_retention_days" {
  description = "How long Ansible reports are kept in S3."
  type        = number
  default     = 400
}

variable "external_member_account_ids" {
  description = "Acquired accounts that are monitored but not yet in the organization."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
