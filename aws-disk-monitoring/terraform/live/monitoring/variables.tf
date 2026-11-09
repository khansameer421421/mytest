variable "organization_id" {
  description = "AWS Organizations ID (o-xxxxxxxxxx)."
  type        = string
}

variable "home_region" {
  description = "Region for central resources (bucket, event bus, SNS, dashboard)."
  type        = string
  default     = "us-east-1"
}

variable "alert_emails" {
  type    = list(string)
  default = []
}

variable "external_member_account_ids" {
  description = "Acquired accounts monitored before they join the organization."
  type        = list(string)
  default     = []
}

variable "controller_subnet_id" {
  description = "Private subnet for the controller instance. Leave null to run Ansible elsewhere (AWX, existing host)."
  type        = string
  default     = null
}

variable "repo_url" {
  description = "Git URL the controller clones."
  type        = string
  default     = "https://github.com/khansameer421421/mytest.git"
}

variable "tags" {
  type    = map(string)
  default = {}
}
