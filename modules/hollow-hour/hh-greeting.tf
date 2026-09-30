# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The two greeting modules, hh-greeting-standard and hh-greeting-halloween,
# each with a version and a live alias. Both are always deployed. The hotline
# invokes module:greeting@live, which hh-hotline-main.flow.tf binds to the live
# alias of var.season, so turning the season on or off changes that one
# binding and no flow's actions (README.md, "The season").
#
# The two greetings share their shape and differ in what they say and in the
# season attribute they set, so they are one resource over this map.

locals {
  greetings = {
    standard = {
      description = "The greeting outside October, released through its live alias."
      text        = "Thank you for calling Hollow Hour Removal Co., the night crew for things that go bump. If anyone is hurt or in danger, hang up and call your local emergency number (911 in the US). This call is recorded so our crews can learn from it."
      season      = "standard"
    }
    halloween = {
      description = "The October greeting, released through its live alias."
      text        = "Happy Halloween from Hollow Hour Removal Co. October is our busiest month, so every crew is on shift tonight. If anyone is hurt or in danger, hang up and call your local emergency number (911 in the US). This call is recorded so our crews can learn from it."
      season      = "halloween-2026"
    }
  }
}

resource "flowascode_contact_flow_module" "hh_greeting" {
  for_each = local.greetings

  instance_id = aws_connect_instance.this.id
  name        = "hh-greeting-${each.key}"
  description = each.value.description
  tags        = local.flow_tags

  settings = jsonencode({
    InputParameters  = []
    OutputParameters = []
    Transitions      = []
  })

  action {
    id   = "greet"
    next = "set-season"
    message_participant {
      text = each.value.text
    }
    error {
      type = "NoMatchingError"
      next = "set-season"
    }
  }

  action {
    id   = "set-season"
    next = "done"
    update_contact_attributes {
      attributes = {
        season = each.value.season
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "done"
    }
  }

  action {
    id = "done"
    end_flow_module_execution {}
  }
}

# A version is a snapshot of the module's current content, replaced whenever
# that content changes. create_before_destroy makes the new version exist
# before the old one goes, and the alias moves to it in place in between:
# Connect refuses to delete a version an alias still points at.
resource "flowascode_contact_flow_module_version" "hh_greeting" {
  for_each = flowascode_contact_flow_module.hh_greeting

  instance_id            = aws_connect_instance.this.id
  contact_flow_module_id = each.value.contact_flow_module_id
  content_hash           = each.value.content_hash
  description            = "${each.value.name} as reviewed (${var.environment})"

  lifecycle {
    create_before_destroy = true
  }
}

# The alias is what the hotline binds: its arn is the module ARN qualified by
# the alias id, the only form Connect runs as the alias.
resource "flowascode_contact_flow_module_alias" "hh_greeting_live" {
  for_each = flowascode_contact_flow_module.hh_greeting

  instance_id                 = aws_connect_instance.this.id
  contact_flow_module_id      = each.value.contact_flow_module_id
  name                        = "live"
  contact_flow_module_version = flowascode_contact_flow_module_version.hh_greeting[each.key].version
  description                 = "The ${each.key} greeting, bound by the hotline when season is ${each.key}"
}
