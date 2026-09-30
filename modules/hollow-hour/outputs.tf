# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# Ids and names an operator needs after an apply. None of them is ever
# written to a committed file; read them with `tofu output`.

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
    [
      flowascode_contact_flow.hh_hotline_main.name,
      flowascode_contact_flow.hh_district_menu.name,
      flowascode_contact_flow.hh_agent_whisper.name,
      flowascode_contact_flow.hh_customer_whisper.name,
    ],
    [for f in flowascode_contact_flow.hh_district : f.name],
    [for f in flowascode_contact_flow.hh_queue_experience : f.name],
    [for m in flowascode_contact_flow_module.hh_greeting : m.name],
  ))
}

# The references each flow binds, by Connect name: the reference key and the
# ARN it resolves to. tests/environments.tftest.hcl reads it to show that the
# season switch moves one binding and nothing else.
output "flow_refs" {
  description = "Each flow's refs map, by Connect name."
  value = merge(
    {
      (flowascode_contact_flow.hh_hotline_main.name)  = flowascode_contact_flow.hh_hotline_main.refs
      (flowascode_contact_flow.hh_district_menu.name) = flowascode_contact_flow.hh_district_menu.refs
    },
    { for f in flowascode_contact_flow.hh_district : f.name => f.refs },
    { for f in flowascode_contact_flow.hh_queue_experience : f.name => f.refs },
  )
}

# The FlowDoc each flow and module reads to, by Connect name: canonical JSON
# with reference tokens in place, computed by the provider at plan time. The
# tests and tools/equivalence/ read it; nothing deploys from it.
output "flowdocs" {
  description = "Each flow's and module's FlowDoc JSON, by Connect name."
  value = merge(
    {
      (flowascode_contact_flow.hh_hotline_main.name)     = flowascode_contact_flow.hh_hotline_main.flowdoc
      (flowascode_contact_flow.hh_district_menu.name)    = flowascode_contact_flow.hh_district_menu.flowdoc
      (flowascode_contact_flow.hh_agent_whisper.name)    = flowascode_contact_flow.hh_agent_whisper.flowdoc
      (flowascode_contact_flow.hh_customer_whisper.name) = flowascode_contact_flow.hh_customer_whisper.flowdoc
    },
    { for f in flowascode_contact_flow.hh_district : f.name => f.flowdoc },
    { for f in flowascode_contact_flow.hh_queue_experience : f.name => f.flowdoc },
    { for m in flowascode_contact_flow_module.hh_greeting : m.name => m.flowdoc },
  )
}

output "greeting_live_arns" {
  description = "Each greeting's live alias ARN, by season: what module:greeting@live binds."
  value       = { for season, alias in flowascode_contact_flow_module_alias.hh_greeting_live : season => alias.arn }
}
