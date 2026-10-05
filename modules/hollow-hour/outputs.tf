# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# Ids and names an operator needs after an apply. None of them is ever
# written to a committed file; read them with `tofu output`.

locals {
  # The flows that are one resource each (the *.flow.tf files and the menu),
  # for the outputs that list every flow. The district and queue-experience
  # flows iterate and are added beside these.
  single_flows = [
    flowascode_contact_flow.hh_hotline_main,
    flowascode_contact_flow.hh_district_menu,
    flowascode_contact_flow.hh_agent_whisper,
    flowascode_contact_flow.hh_customer_whisper,
    flowascode_contact_flow.hh_customer_hold,
    flowascode_contact_flow.hh_agent_hold,
    flowascode_contact_flow.hh_dead_line,
    flowascode_contact_flow.hh_dead_whisper,
    flowascode_contact_flow.hh_dead_hold,
    flowascode_contact_flow.hh_dead_queue_experience,
  ]
}

output "instance_id" {
  description = "The Connect instance id: what the AWS CLI calls take as --instance-id."
  value       = aws_connect_instance.this.id
}

output "instance_arn" {
  description = "The Connect instance ARN: the --context-id of the instance-level service quotas."
  value       = aws_connect_instance.this.arn
}

output "instance_alias" {
  description = "The instance alias, and so its sign-in domain (<alias>.my.connect.aws)."
  value       = aws_connect_instance.this.instance_alias
}

output "flow_log_group_name" {
  description = "The instance's flow log group, /aws/connect/<alias>: created here when manage_flow_log_group is true, by Connect otherwise."
  value       = "/aws/connect/${aws_connect_instance.this.instance_alias}"
}

output "season" {
  description = "Which greeting the hotline invokes through its live alias."
  value       = var.season
}

output "district_hours" {
  description = "The hours profile each district's crew keeps, by slug."
  value       = local.district_hours
}

output "lambda_function_names" {
  description = "The stub functions, by name, for logs and a manual invoke."
  value       = { for name, fn in aws_lambda_function.stub : name => fn.function_name }
}

output "flow_names" {
  description = "Every flow and module this module deploys, by Connect name."
  value = sort(concat(
    [for f in local.single_flows : f.name],
    [for f in flowascode_contact_flow.hh_district : f.name],
    [for f in flowascode_contact_flow.hh_queue_experience : f.name],
    [for m in flowascode_contact_flow_module.hh_greeting : m.name],
    [flowascode_contact_flow_module.hh_offer_callback.name],
  ))
}

# The references each flow binds, by Connect name: the reference key and the
# ARN it resolves to. tests/environments.tftest.hcl reads it to show that the
# season switch moves one binding and nothing else.
output "flow_refs" {
  description = "Each flow's and module's refs map, by Connect name."
  value = merge(
    { for f in local.single_flows : f.name => f.refs if f.refs != null },
    { for f in flowascode_contact_flow.hh_district : f.name => f.refs },
    { for f in flowascode_contact_flow.hh_queue_experience : f.name => f.refs },
    { (flowascode_contact_flow_module.hh_offer_callback.name) = flowascode_contact_flow_module.hh_offer_callback.refs },
  )
}

# The FlowDoc each flow and module reads to, by Connect name: canonical JSON
# with reference tokens in place, computed by the provider at plan time. The
# tests and tools/equivalence/ read it; nothing deploys from it.
output "flowdocs" {
  description = "Each flow's and module's FlowDoc JSON, by Connect name."
  value = merge(
    { for f in local.single_flows : f.name => f.flowdoc },
    { for f in flowascode_contact_flow.hh_district : f.name => f.flowdoc },
    { for f in flowascode_contact_flow.hh_queue_experience : f.name => f.flowdoc },
    { for m in flowascode_contact_flow_module.hh_greeting : m.name => m.flowdoc },
    { (flowascode_contact_flow_module.hh_offer_callback.name) = flowascode_contact_flow_module.hh_offer_callback.flowdoc },
  )
}

output "recording_bucket" {
  description = "The call recording bucket (recordings.tf): SSE-S3, 30-day expiry, named under the amazon-connect- prefix the service-linked role can write to."
  value       = aws_s3_bucket.recordings.bucket
}

output "prompt_bucket" {
  description = "The prompt audio bucket (prompts.tf): private, SSE-S3, holding the one committed wav the Connect prompt is made from."
  value       = aws_s3_bucket.prompts.bucket
}

output "offer_callback_live_arn" {
  description = "The callback module's live alias ARN: what the district flows bind as module:hh-offer-callback@live."
  value       = flowascode_contact_flow_module_alias.hh_offer_callback_live.arn
}

output "greeting_live_arns" {
  description = "Each greeting's live alias ARN, by season: what module:greeting@live binds."
  value       = { for season, alias in flowascode_contact_flow_module_alias.hh_greeting_live : season => alias.arn }
}
