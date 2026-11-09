# Root configuration applied to EVERY member account - one Terraform
# workspace (= one state file) per account. scripts/tf-members.sh loops over
# the accounts in AWS Organizations; AFT account customizations can call the
# same modules for zero-touch onboarding (see README).
#
# Terraform reaches the account through the role Organizations creates in
# every new account (OrganizationAccountAccessRole by default).

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {}
}

locals {
  role_arn = "arn:aws:iam::${var.account_id}:role/${var.bootstrap_role_name}"
  tags     = merge(var.tags, { Project = "disk-monitoring", ManagedBy = "terraform" })
}

provider "aws" {
  region = var.home_region
  assume_role {
    role_arn     = local.role_arn
    session_name = "terraform-disk-monitoring"
  }
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
  assume_role {
    role_arn     = local.role_arn
    session_name = "terraform-disk-monitoring"
  }
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
  assume_role {
    role_arn     = local.role_arn
    session_name = "terraform-disk-monitoring"
  }
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "eu_central_1"
  region = "eu-central-1"
  assume_role {
    role_arn     = local.role_arn
    session_name = "terraform-disk-monitoring"
  }
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = local.tags
  }
}

# ------------------------------------------------------------- global IAM --

module "baseline" {
  source = "../../modules/member-baseline"

  controller_role_arn   = var.controller_role_arn
  organization_id       = var.in_organization ? var.organization_id : null
  artifact_bucket_name  = var.artifact_bucket_name
  central_event_bus_arn = var.central_event_bus_arn
}

# ------------------------------------------------------- regional pieces --

module "regional_home" {
  source = "../../modules/member-regional"
  count  = contains(var.regions, var.home_region) ? 1 : 0

  sink_arn                = var.sink_arns[var.home_region]
  central_event_bus_arn   = var.central_event_bus_arn
  events_forward_role_arn = module.baseline.events_forward_role_arn
  backstop_threshold      = var.backstop_threshold
}

module "regional_us_west_2" {
  source    = "../../modules/member-regional"
  count     = contains(var.regions, "us-west-2") ? 1 : 0
  providers = { aws = aws.us_west_2 }

  sink_arn                = var.sink_arns["us-west-2"]
  central_event_bus_arn   = var.central_event_bus_arn
  events_forward_role_arn = module.baseline.events_forward_role_arn
  backstop_threshold      = var.backstop_threshold
}

module "regional_eu_west_1" {
  source    = "../../modules/member-regional"
  count     = contains(var.regions, "eu-west-1") ? 1 : 0
  providers = { aws = aws.eu_west_1 }

  sink_arn                = var.sink_arns["eu-west-1"]
  central_event_bus_arn   = var.central_event_bus_arn
  events_forward_role_arn = module.baseline.events_forward_role_arn
  backstop_threshold      = var.backstop_threshold
}

module "regional_eu_central_1" {
  source    = "../../modules/member-regional"
  count     = contains(var.regions, "eu-central-1") ? 1 : 0
  providers = { aws = aws.eu_central_1 }

  sink_arn                = var.sink_arns["eu-central-1"]
  central_event_bus_arn   = var.central_event_bus_arn
  events_forward_role_arn = module.baseline.events_forward_role_arn
  backstop_threshold      = var.backstop_threshold
}

output "ansible_role_arn" {
  value = module.baseline.ansible_role_arn
}

output "instance_profile_name" {
  value = module.baseline.instance_profile_name
}
