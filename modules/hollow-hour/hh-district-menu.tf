# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# hh-district-menu: "Where are you calling from?", one keypad digit per
# district in var.districts order, then the district's flow; no answer, or
# any error, goes to dispatch. The prompt, the conditions and the per-district
# actions are all built from var.districts, so adding a district is one entry
# there and the menu grows a key.

locals {
  district_menu_prompt = join(" ", concat(
    ["Where are you calling from?"],
    [for i, d in var.districts : "For ${d.name}, press ${i + 1}."],
  ))

  district_menu_routes = flatten([
    for d in var.districts : [
      { kind = "route", id = "route-${d.slug}", next = "to-${d.slug}", district = d },
      { kind = "transfer", id = "to-${d.slug}", next = "hang-up", district = d },
    ]
  ])
}

resource "flowascode_contact_flow" "hh_district_menu" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-district-menu"
  type        = "CONTACT_FLOW"
  description = "The keypad district menu, one key per district in var.districts order."
  tags        = local.flow_tags

  refs = merge(
    {
      "flow:hh-agent-hold"       = flowascode_contact_flow.hh_agent_hold.arn
      "flow:hh-agent-whisper"    = flowascode_contact_flow.hh_agent_whisper.arn
      "flow:hh-customer-hold"    = flowascode_contact_flow.hh_customer_hold.arn
      "flow:hh-customer-whisper" = flowascode_contact_flow.hh_customer_whisper.arn
      "queue:dispatch-overflow"  = aws_connect_queue.shared["dispatch-overflow"].arn
    },
    { for d in var.districts : "flow:hh-district-${d.slug}" => flowascode_contact_flow.hh_district[d.slug].arn },
  )

  action {
    id   = "ask-district"
    next = "hand-to-dispatch"
    get_participant_input {
      input_time_limit_seconds = 8
      store_input              = "False"
      text                     = local.district_menu_prompt
    }
    dynamic "condition" {
      for_each = var.districts
      content {
        operator = "Equals"
        operands = [tostring(condition.key + 1)]
        next     = "route-${condition.value.slug}"
      }
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "hand-to-dispatch"
    }
    error {
      type = "NoMatchingCondition"
      next = "hand-to-dispatch"
    }
    error {
      type = "NoMatchingError"
      next = "hand-to-dispatch"
    }
  }

  # Per district, in keypad order: note the district on the contact, then
  # transfer to its flow. The two actions interleave (route-<slug>,
  # to-<slug>, then the next district's), as a hand-written flow would.
  dynamic "action" {
    for_each = local.district_menu_routes
    content {
      id   = action.value.id
      next = action.value.next

      dynamic "update_contact_attributes" {
        for_each = action.value.kind == "route" ? [action.value.district] : []
        content {
          attributes = {
            district     = update_contact_attributes.value.slug
            districtName = update_contact_attributes.value.name
          }
          target_contact = "Current"
        }
      }

      dynamic "transfer_to_flow" {
        for_each = action.value.kind == "transfer" ? [action.value.district] : []
        content {
          contact_flow_id = "flow:hh-district-${transfer_to_flow.value.slug}"
        }
      }

      error {
        type = "NoMatchingError"
        next = "hand-to-dispatch"
      }
    }
  }

  action {
    id   = "hand-to-dispatch"
    next = "note-dispatch"
    message_participant {
      text = "Let me put you through to a dispatcher."
    }
    error {
      type = "NoMatchingError"
      next = "note-dispatch"
    }
  }

  action {
    id   = "note-dispatch"
    next = "set-dispatch-customer-whisper"
    update_contact_attributes {
      attributes = {
        districtName = "Dispatch"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "set-dispatch-customer-whisper"
    }
  }

  action {
    id   = "set-dispatch-customer-whisper"
    next = "set-dispatch-agent-whisper"
    update_contact_event_hooks {
      event_hooks = {
        CustomerWhisper = "$${cdref:flow:hh-customer-whisper}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dispatch-agent-whisper"
    }
  }

  action {
    id   = "set-dispatch-agent-whisper"
    next = "set-dispatch-customer-hold"
    update_contact_event_hooks {
      event_hooks = {
        AgentWhisper = "$${cdref:flow:hh-agent-whisper}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dispatch-customer-hold"
    }
  }

  action {
    id   = "set-dispatch-customer-hold"
    next = "set-dispatch-agent-hold"
    update_contact_event_hooks {
      event_hooks = {
        CustomerHold = "$${cdref:flow:hh-customer-hold}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dispatch-agent-hold"
    }
  }

  action {
    id   = "set-dispatch-agent-hold"
    next = "set-dispatch-queue"
    update_contact_event_hooks {
      event_hooks = {
        AgentHold = "$${cdref:flow:hh-agent-hold}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dispatch-queue"
    }
  }

  action {
    id   = "set-dispatch-queue"
    next = "transfer-to-dispatch"
    update_contact_target_queue {
      queue_id = "queue:dispatch-overflow"
    }
    error {
      type = "NoMatchingError"
      next = "apologize"
    }
  }

  action {
    id   = "transfer-to-dispatch"
    next = "hang-up"
    transfer_contact_to_queue {}
    error {
      type = "QueueAtCapacity"
      next = "lines-busy"
    }
    error {
      type = "NoMatchingError"
      next = "apologize"
    }
  }

  action {
    id   = "lines-busy"
    next = "hang-up"
    message_participant {
      text = "Every crew is out on a call. Please call back in a few minutes."
    }
    error {
      type = "NoMatchingError"
      next = "hang-up"
    }
  }

  action {
    id   = "apologize"
    next = "hang-up"
    message_participant {
      text = "Something went wrong on our side. Please call back in a few minutes."
    }
    error {
      type = "NoMatchingError"
      next = "hang-up"
    }
  }

  action {
    id = "hang-up"
    disconnect_participant {}
  }
}
