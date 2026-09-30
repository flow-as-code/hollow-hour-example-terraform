# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# What the flows read to, checked on the FlowDocs the real flowascode provider
# computes at plan time (its flowdoc attribute: the document with reference
# tokens in place). aws is mocked, so nothing is created and no credential is
# needed; flowascode is real but only plans, and planning makes no AWS call.
#
# Holds: every Compare carries next (Connect refuses one without
# Transitions.NextAction); every reference a flow makes is bound in its refs
# and every refs key is used; no ARN is written into a flow; one district
# flow and one queue-experience flow per district, and a menu key each; the
# queue cap per environment; every flow and module carries the tags; the
# flow log group is optional; the variables refuse a broken overflow and
# values AWS would refuse at apply. tests/environments.tftest.hcl compares
# the profiles.

mock_provider "aws" {
  # Shapes the aws provider validates: an IAM policy that parses and ARNs
  # that parse. 000000000000 and the zero UUID are placeholders. Everything
  # else is generated.
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_connect_instance" {
    defaults = { arn = "arn:aws:connect:us-east-1:000000000000:instance/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::000000000000:role/mock" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:000000000000:function:mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:000000000000:log-group:mock" }
  }
}

provider "flowascode" {
  region                      = "us-east-1"
  access_key                  = "offline"
  secret_key                  = "offline"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

variables {
  environment = "prod"
  hours       = "night_shift"
  season      = "standard"
}

run "prod" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  assert {
    condition = toset(keys(output.flowdocs)) == toset([
      "hh-agent-whisper",
      "hh-customer-whisper",
      "hh-district-graveyard-hill",
      "hh-district-harborside",
      "hh-district-menu",
      "hh-district-old-town",
      "hh-greeting-halloween",
      "hh-greeting-standard",
      "hh-hotline-main",
      "hh-queue-experience-graveyard-hill",
      "hh-queue-experience-harborside",
      "hh-queue-experience-old-town",
    ])
    error_message = "The module deploys the ten Tier 1 flows and the two greeting modules, named as in the TypeScript-first repository."
  }

  assert {
    condition = alltrue(flatten([
      for name, doc in output.flowdocs : [
        for a in jsondecode(doc).content.Actions :
        try(a.Transitions.NextAction, "") != "" if a.Type == "Compare"
      ]
    ]))
    error_message = "A Compare has no next. Connect refuses a Compare without Transitions.NextAction (VERIFY.md, C1): set next to its NoMatchingCondition target."
  }

  assert {
    condition = length(flatten([
      for name, doc in output.flowdocs : [
        for a in jsondecode(doc).content.Actions : a if a.Type == "Compare"
      ]
    ])) == 5
    error_message = "Expected five Compares (check-caller, check-grade, and check-moved per district); the Compare check above would pass vacuously on none."
  }

  assert {
    condition = alltrue([
      for name, refs in output.flow_refs :
      toset(keys(refs)) == toset([
        for r in jsondecode(output.flowdocs[name]).refs :
        trimsuffix(trimprefix(r.token, "$${cdref:"), "}")
      ])
    ])
    error_message = "A flow's refs and the references its actions make differ: every reference key an action uses is bound in refs, and every refs key is used."
  }

  assert {
    condition     = alltrue([for name, doc in output.flowdocs : !strcontains(jsondecode(doc).content == null ? "" : jsonencode(jsondecode(doc).content), "arn:")])
    error_message = "A flow's content holds an ARN. References are tokens bound through refs, never literal ARNs."
  }

  assert {
    condition     = keys(aws_connect_queue.crew) == ["graveyard-hill", "harborside", "old-town"]
    error_message = "One crew queue per district."
  }

  assert {
    condition     = keys(flowascode_contact_flow.hh_district) == keys(aws_connect_queue.crew) && keys(flowascode_contact_flow.hh_queue_experience) == keys(aws_connect_queue.crew)
    error_message = "One district flow and one queue-experience flow per district."
  }

  assert {
    condition     = output.district_hours == { "old-town" = "night_shift", "harborside" = "night_shift", "graveyard-hill" = "night_shift" }
    error_message = "Every district crew keeps the environment's hours profile unless its entry names another."
  }

  assert {
    condition     = jsondecode(output.flowdocs["hh-district-menu"]).content.Actions[0].Parameters.Text == "Where are you calling from? For Old Town, press 1. For Harborside, press 2. For Graveyard Hill, press 3."
    error_message = "The menu prompt names each district with its key, in var.districts order."
  }

  assert {
    condition = [
      for c in jsondecode(output.flowdocs["hh-district-menu"]).content.Actions[0].Transitions.Conditions :
      "${c.Condition.Operands[0]}:${c.NextAction}"
    ] == ["1:route-old-town", "2:route-harborside", "3:route-graveyard-hill"]
    error_message = "Menu key n routes to the nth district."
  }

  assert {
    condition     = aws_connect_queue.crew["old-town"].max_contacts == 25 && aws_connect_queue.shared["dispatch-overflow"].max_contacts == 25
    error_message = "prod queues hold 25 contacts."
  }

  # flowascode has no default_tags, so the module tags each flow and module.
  assert {
    condition = alltrue(concat(
      [for f in concat(
        [flowascode_contact_flow.hh_hotline_main, flowascode_contact_flow.hh_district_menu, flowascode_contact_flow.hh_agent_whisper, flowascode_contact_flow.hh_customer_whisper],
        values(flowascode_contact_flow.hh_district),
        values(flowascode_contact_flow.hh_queue_experience),
      ) : f.tags == tomap({ "hollow-hour-example-terraform" = "true", "environment" = "prod" })],
      [for m in values(flowascode_contact_flow_module.hh_greeting) : m.tags == tomap({ "hollow-hour-example-terraform" = "true", "environment" = "prod" })],
    ))
    error_message = "Every flow and module carries the hollow-hour-example-terraform and environment tags."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.connect_flow_logs) == 1 && aws_cloudwatch_log_group.connect_flow_logs[0].retention_in_days == 14
    error_message = "By default the module creates the flow log group, with 14 days of retention."
  }
}

# The fallback if Connect refuses a log group that already exists (VERIFY.md,
# T1): no group here, and the instance still plans.
run "flow_log_group_left_to_connect" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    manage_flow_log_group = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.connect_flow_logs) == 0 && aws_connect_instance.this.contact_flow_logs_enabled
    error_message = "With manage_flow_log_group false the module creates no flow log group, and flow logs stay enabled."
  }
}

# Values AWS would refuse at apply are refused at plan.
run "inputs_aws_would_refuse" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    log_retention_days = 10
    instance_alias     = "d-0123456789"
    name_prefix        = "tfacc-hh"
    queue_max_contacts = 0
    time_zone          = "America/New York"
  }

  expect_failures = [
    var.log_retention_days,
    var.instance_alias,
    var.name_prefix,
    var.queue_max_contacts,
    var.time_zone,
  ]
}

run "alias_longer_than_45_refused" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    instance_alias = "hollow-hour-tf-an-alias-that-is-far-too-long-to-use"
    name_prefix    = "HH"
  }

  expect_failures = [var.instance_alias, var.name_prefix]
}

run "valid_inputs_accepted" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    log_retention_days = 30
    instance_alias     = "hollow-hour-tf-adopted-1"
    name_prefix        = "hh-tf2"
    queue_max_contacts = 5
    time_zone          = "UTC"
  }

  assert {
    condition     = aws_connect_instance.this.instance_alias == "hollow-hour-tf-adopted-1" && aws_connect_queue.crew["old-town"].max_contacts == 5
    error_message = "Valid inputs are taken as given."
  }
}

run "dev_queue_cap" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    environment = "dev"
    hours       = "always_open"
  }

  assert {
    condition     = alltrue([for q in values(aws_connect_queue.crew) : q.max_contacts == 2]) && alltrue([for q in values(aws_connect_queue.shared) : q.max_contacts == 2])
    error_message = "Outside prod every queue holds two contacts, so an operator can fill one and hear the overflow."
  }
}

# A fourth district is one entry: its queue, its two flows, and a menu key.
run "four_districts" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    districts = [
      { slug = "old-town", name = "Old Town", overflow_to = "harborside" },
      { slug = "harborside", name = "Harborside", overflow_to = "graveyard-hill" },
      { slug = "graveyard-hill", name = "Graveyard Hill", overflow_to = "mill-pond" },
      { slug = "mill-pond", name = "Mill Pond", overflow_to = "old-town", hours = "always_open" },
    ]
  }

  assert {
    condition     = length(output.flowdocs) == 14 && length(aws_connect_queue.crew) == 4
    error_message = "A fourth district adds one crew queue, one district flow and one queue-experience flow."
  }

  assert {
    condition     = endswith(jsondecode(output.flowdocs["hh-district-menu"]).content.Actions[0].Parameters.Text, "For Mill Pond, press 4.")
    error_message = "The menu grows a fourth key."
  }

  assert {
    condition     = output.district_hours["mill-pond"] == "always_open" && output.district_hours["old-town"] == "night_shift"
    error_message = "A district's own hours override the environment's for that district only."
  }

  assert {
    condition     = contains(keys(output.flow_refs["hh-district-graveyard-hill"]), "queue:mill-pond-crew")
    error_message = "Graveyard Hill overflows to its overflow_to, Mill Pond."
  }
}

run "overflow_must_be_a_sibling" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    districts = [
      { slug = "old-town", name = "Old Town", overflow_to = "old-town" },
      { slug = "harborside", name = "Harborside", overflow_to = "nowhere" },
    ]
  }

  expect_failures = [var.districts]
}

run "season_is_standard_or_halloween" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    season = "october"
  }

  expect_failures = [var.season]
}
