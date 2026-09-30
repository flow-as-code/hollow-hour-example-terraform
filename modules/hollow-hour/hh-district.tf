# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# hh-district-<slug>, one per entry of var.districts: set the crew queue and
# the whispers and queue experience, check the crew's hours, then transfer;
# a full queue moves the caller to the overflow sibling's crew with the
# district attributes changed to match, and anything that errors goes to
# dispatch.
#
# One resource over the districts rather than a copy per district: every
# district's flow has the same actions, and differs only in the names and
# references interpolated from each.value. Adding a district is one entry in
# var.districts.

locals {
  # Each district with its overflow sibling, as the district and
  # queue-experience flows read them.
  district_flows = {
    for d in var.districts : d.slug => {
      slug    = d.slug
      name    = d.name
      sibling = local.districts[d.overflow_to]
    }
  }
}

resource "flowascode_contact_flow" "hh_district" {
  for_each = local.district_flows

  instance_id = aws_connect_instance.this.id
  name        = "hh-district-${each.key}"
  type        = "CONTACT_FLOW"
  description = "Dispatch for ${each.value.name}: the crew's hours, then its queue, then ${each.value.sibling.name} when the queue is full."
  tags        = local.flow_tags

  refs = {
    "flow:hh-agent-whisper"                               = flowascode_contact_flow.hh_agent_whisper.arn
    "flow:hh-customer-whisper"                            = flowascode_contact_flow.hh_customer_whisper.arn
    "flow:hh-queue-experience-${each.key}"                = flowascode_contact_flow.hh_queue_experience[each.key].arn
    "flow:hh-queue-experience-${each.value.sibling.slug}" = flowascode_contact_flow.hh_queue_experience[each.value.sibling.slug].arn
    "hours:${each.key}"                                   = aws_connect_hours_of_operation.profile[local.district_hours[each.key]].arn
    "queue:dispatch-overflow"                             = aws_connect_queue.shared["dispatch-overflow"].arn
    "queue:${each.key}-crew"                              = aws_connect_queue.crew[each.key].arn
    "queue:${each.value.sibling.slug}-crew"               = aws_connect_queue.crew[each.value.sibling.slug].arn
  }

  action {
    id   = "set-crew-queue"
    next = "set-customer-whisper"
    update_contact_target_queue {
      queue_id = "queue:${each.key}-crew"
    }
    error {
      type = "NoMatchingError"
      next = "hand-to-dispatch"
    }
  }

  action {
    id   = "set-customer-whisper"
    next = "set-agent-whisper"
    update_contact_event_hooks {
      event_hooks = {
        CustomerWhisper = "$${cdref:flow:hh-customer-whisper}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-agent-whisper"
    }
  }

  action {
    id   = "set-agent-whisper"
    next = "set-queue-experience"
    update_contact_event_hooks {
      event_hooks = {
        AgentWhisper = "$${cdref:flow:hh-agent-whisper}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-queue-experience"
    }
  }

  action {
    id   = "set-queue-experience"
    next = "note-overflow-crew"
    update_contact_event_hooks {
      event_hooks = {
        CustomerQueue = "$${cdref:flow:hh-queue-experience-${each.key}}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "note-overflow-crew"
    }
  }

  action {
    id   = "note-overflow-crew"
    next = "check-hours"
    update_flow_attributes {
      flow_attributes = {
        overflowCrew = {
          value = each.value.sibling.name
        }
      }
    }
    error {
      type = "NoMatchingError"
      next = "check-hours"
    }
  }

  action {
    id   = "check-hours"
    next = "after-hours"
    check_hours_of_operation {
      hours_of_operation_id = "hours:${each.key}"
    }
    condition {
      operator = "Equals"
      operands = ["True"]
      next     = "check-staffing"
    }
    condition {
      operator = "Equals"
      operands = ["False"]
      next     = "after-hours"
    }
    error {
      type = "NoMatchingError"
      next = "check-staffing"
    }
  }

  action {
    id   = "check-staffing"
    next = "transfer-to-crew"
    check_metric_data {
      metric_type = "NumberOfAgentsAvailable"
      queue_id    = "queue:${each.key}-crew"
    }
    condition {
      operator = "NumberGreaterThan"
      operands = ["0"]
      next     = "crew-ready"
    }
    error {
      type = "NoMatchingError"
      next = "transfer-to-crew"
    }
    error {
      type = "NoMatchingCondition"
      next = "read-queue"
    }
  }

  action {
    id   = "crew-ready"
    next = "transfer-to-crew"
    message_participant {
      text = "The ${each.value.name} crew has someone free. Connecting you now."
    }
    error {
      type = "NoMatchingError"
      next = "transfer-to-crew"
    }
  }

  action {
    id   = "read-queue"
    next = "announce-line"
    get_metric_data {
      queue_id = "queue:${each.key}-crew"
    }
    error {
      type = "NoMatchingError"
      next = "transfer-to-crew"
    }
  }

  action {
    id   = "announce-line"
    next = "transfer-to-crew"
    message_participant {
      text = "The ${each.value.name} crew is out on calls. Callers ahead of you: $.Metrics.Queue.Size. Stay on the line and we will keep your place."
    }
    error {
      type = "NoMatchingError"
      next = "transfer-to-crew"
    }
  }

  action {
    id   = "transfer-to-crew"
    next = "hang-up"
    transfer_contact_to_queue {}
    error {
      type = "QueueAtCapacity"
      next = "crew-full"
    }
    error {
      type = "NoMatchingError"
      next = "apologize"
    }
  }

  action {
    id   = "crew-full"
    next = "note-overflow-district"
    message_participant {
      text = "The ${each.value.name} crew is full tonight. Moving you to the $.FlowAttributes.overflowCrew crew."
    }
    error {
      type = "NoMatchingError"
      next = "note-overflow-district"
    }
  }

  action {
    id   = "note-overflow-district"
    next = "set-overflow-queue-experience"
    update_contact_attributes {
      attributes = {
        district     = each.value.sibling.slug
        districtName = each.value.sibling.name
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "set-overflow-queue-experience"
    }
  }

  action {
    id   = "set-overflow-queue-experience"
    next = "set-overflow-queue"
    update_contact_event_hooks {
      event_hooks = {
        CustomerQueue = "$${cdref:flow:hh-queue-experience-${each.value.sibling.slug}}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-overflow-queue"
    }
  }

  action {
    id   = "set-overflow-queue"
    next = "transfer-to-overflow"
    update_contact_target_queue {
      queue_id = "queue:${each.value.sibling.slug}-crew"
    }
    error {
      type = "NoMatchingError"
      next = "apologize"
    }
  }

  action {
    id   = "transfer-to-overflow"
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
    id   = "after-hours"
    next = "hang-up"
    message_participant {
      text = "The ${each.value.name} crew is off shift right now. Night crews start at 4 in the afternoon. If anyone is hurt or in danger, call your local emergency number (911 in the US)."
    }
    error {
      type = "NoMatchingError"
      next = "hang-up"
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
    next = "set-dispatch-queue"
    update_contact_event_hooks {
      event_hooks = {
        AgentWhisper = "$${cdref:flow:hh-agent-whisper}"
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
