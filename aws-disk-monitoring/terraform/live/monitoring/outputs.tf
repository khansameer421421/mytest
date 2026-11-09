# scripts/tf-members.sh turns these outputs into member.auto.tfvars.json for
# the member configuration.

output "member_inputs" {
  value = {
    organization_id       = var.organization_id
    controller_role_arn   = module.central.controller_role_arn
    artifact_bucket_name  = module.central.artifact_bucket_name
    central_event_bus_arn = module.central.central_event_bus_arn
    sink_arns = {
      (var.home_region) = module.sink_home.sink_arn
      "us-west-2"       = module.sink_us_west_2.sink_arn
      "eu-west-1"       = module.sink_eu_west_1.sink_arn
      "eu-central-1"    = module.sink_eu_central_1.sink_arn
    }
  }
}

output "alert_topic_arn" {
  value = module.central.alert_topic_arn
}

output "controller_instance_id" {
  value = one(module.controller[*].instance_id)
}
