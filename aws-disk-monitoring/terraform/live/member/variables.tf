variable "account_id" {
  description = "Member account to configure (set per workspace by scripts/tf-members.sh)."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "bootstrap_role_name" {
  description = "Role Terraform assumes in the member account."
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "in_organization" {
  description = "false for an acquired account that has not joined the organization yet."
  type        = bool
  default     = true
}

variable "home_region" {
  type    = string
  default = "us-east-1"
}

variable "regions" {
  description = "Monitored regions in this account."
  type        = list(string)
  default     = ["us-east-1", "us-west-2", "eu-west-1"]
}

variable "backstop_threshold" {
  type    = number
  default = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ---- outputs of live/monitoring (written to member.auto.tfvars.json) ----

variable "organization_id" {
  type = string
}

variable "controller_role_arn" {
  type = string
}

variable "artifact_bucket_name" {
  type = string
}

variable "central_event_bus_arn" {
  type = string
}

variable "sink_arns" {
  description = "OAM sink ARN per region."
  type        = map(string)
}
