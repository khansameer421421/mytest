# Root configuration for the monitoring (tooling) account.
#
#   terraform init -backend-config=../backend.hcl -backend-config="key=disk-monitoring/monitoring.tfstate"
#   terraform apply -var-file=monitoring.tfvars
#
# Monitored regions: one provider alias + one sink module per region. To add
# a region, copy one provider block and one module "sink_*" block.

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
  tags = merge(var.tags, { Project = "disk-monitoring", ManagedBy = "terraform" })
}

provider "aws" {
  region = var.home_region
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
  default_tags {
    tags = local.tags
  }
}

provider "aws" {
  alias  = "eu_central_1"
  region = "eu-central-1"
  default_tags {
    tags = local.tags
  }
}

module "central" {
  source = "../../modules/monitoring-central"

  organization_id             = var.organization_id
  alert_emails                = var.alert_emails
  external_member_account_ids = var.external_member_account_ids
}

# ---------------------------------------------------- OAM sinks per region --

module "sink_home" {
  source          = "../../modules/monitoring-sink"
  organization_id = var.organization_id
}

module "sink_us_west_2" {
  source          = "../../modules/monitoring-sink"
  providers       = { aws = aws.us_west_2 }
  organization_id = var.organization_id
}

module "sink_eu_west_1" {
  source          = "../../modules/monitoring-sink"
  providers       = { aws = aws.eu_west_1 }
  organization_id = var.organization_id
}

module "sink_eu_central_1" {
  source          = "../../modules/monitoring-sink"
  providers       = { aws = aws.eu_central_1 }
  organization_id = var.organization_id
}

# ------------------------------------------------- optional controller VM --

module "controller" {
  source = "../../modules/controller"
  count  = var.controller_subnet_id == null ? 0 : 1

  subnet_id             = var.controller_subnet_id
  instance_profile_name = module.central.controller_instance_profile
  repo_url              = var.repo_url
}
