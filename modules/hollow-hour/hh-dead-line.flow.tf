# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# hh-dead-line: the line for the departed, reached from hh-hotline-main when
# lambda:plane-check says the caller is beyond, after the safety question
# and never before it. The welcome speaks first and says the call is
# recorded; only then does record-agent-only record the liaison's side alone
# (RecordedParticipants ["Agent"] still enables recording, so the notice
# comes first). Then the four event hooks, one per block, the Beyond
# attributes, the routing adjustment (-300 s of patience: the living go
# first tonight), the callback number with both of its errors wired, the
# hours that never close (both branches continue), and the Queue of the
# Dead. The TypeScript-first repository's VERIFY.md, rows 16.3, 16.4, 16.5
# and 6.2, hold the service behaviors this relies on.

resource "flowascode_contact_flow" "hh_dead_line" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-dead-line"
  type        = "CONTACT_FLOW"
  description = "The line for the departed, reached from hh-hotline-main when plane-check says the caller is beyond. Welcome first, then agent-only recording, the four hooks, patience, the callback number, the hours that never close, and the Queue of the Dead."
  tags        = local.flow_tags

  # hours:the-dead is the always-open profile: the dead never close.
  refs = {
    "flow:hh-agent-hold"            = flowascode_contact_flow.hh_agent_hold.arn
    "flow:hh-dead-hold"             = flowascode_contact_flow.hh_dead_hold.arn
    "flow:hh-dead-queue-experience" = flowascode_contact_flow.hh_dead_queue_experience.arn
    "flow:hh-dead-whisper"          = flowascode_contact_flow.hh_dead_whisper.arn
    "hours:the-dead"                = aws_connect_hours_of_operation.profile["always_open"].arn
    "queue:the-dead"                = aws_connect_queue.shared["the-dead"].arn
  }

  action {
    id   = "dead-welcome"
    next = "record-agent-only"
    message_participant {
      text = "You have reached the Hollow Hour line for the departed. Calls are recorded, but only our liaison's side, never yours. You are welcome here, and we are glad you called."
    }
    error {
      type = "NoMatchingError"
      next = "record-agent-only"
    }
  }

  # No error branch: the catalog models none for this block (rule 37).
  action {
    id   = "record-agent-only"
    next = "set-dead-whisper"
    update_contact_recording_behavior {
      recording_behavior = {
        recorded_participants = ["Agent"]
      }
    }
  }

  action {
    id   = "set-dead-whisper"
    next = "set-dead-hold"
    update_contact_event_hooks {
      event_hooks = {
        AgentWhisper = "$${cdref:flow:hh-dead-whisper}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dead-hold"
    }
  }

  action {
    id   = "set-dead-hold"
    next = "set-dead-queue-experience"
    update_contact_event_hooks {
      event_hooks = {
        CustomerHold = "$${cdref:flow:hh-dead-hold}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dead-queue-experience"
    }
  }

  action {
    id   = "set-dead-queue-experience"
    next = "set-dead-agent-hold"
    update_contact_event_hooks {
      event_hooks = {
        CustomerQueue = "$${cdref:flow:hh-dead-queue-experience}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dead-agent-hold"
    }
  }

  action {
    id   = "set-dead-agent-hold"
    next = "note-beyond"
    update_contact_event_hooks {
      event_hooks = {
        AgentHold = "$${cdref:flow:hh-agent-hold}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "note-beyond"
    }
  }

  # hh-agent-hold speaks gradeName, and the district-name walk needs a name
  # to hold queue:the-dead to.
  action {
    id   = "note-beyond"
    next = "set-patience"
    update_contact_attributes {
      attributes = {
        district     = "beyond"
        districtName = "Beyond"
        gradeName    = "Departed"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "set-patience"
    }
  }

  # Static and negative, never with a priority, and before the target queue
  # and the transfer.
  action {
    id   = "set-patience"
    next = "set-callback-number"
    update_contact_routing_behavior {
      queue_time_adjustment_seconds = -300
    }
  }

  action {
    id   = "set-callback-number"
    next = "check-dead-hours"
    update_contact_callback_number {
      callback_number = "$.CustomerEndpoint.Address"
    }
    error {
      type = "InvalidCallbackNumber"
      next = "cannot-ring-back"
    }
    error {
      type = "CallbackNumberNotDialable"
      next = "cannot-ring-back"
    }
  }

  action {
    id   = "cannot-ring-back"
    next = "check-dead-hours"
    message_participant {
      text = "We cannot ring you back where you are, so stay on the line."
    }
    error {
      type = "NoMatchingError"
      next = "check-dead-hours"
    }
  }

  action {
    id   = "check-dead-hours"
    next = "set-dead-queue"
    check_hours_of_operation {
      hours_of_operation_id = "hours:the-dead"
    }
    condition {
      operator = "Equals"
      operands = ["True"]
      next     = "set-dead-queue"
    }
    condition {
      operator = "Equals"
      operands = ["False"]
      next     = "set-dead-queue"
    }
    error {
      type = "NoMatchingError"
      next = "set-dead-queue"
    }
  }

  action {
    id   = "set-dead-queue"
    next = "transfer-to-dead"
    update_contact_target_queue {
      queue_id = "queue:the-dead"
    }
    error {
      type = "NoMatchingError"
      next = "apologize"
    }
  }

  action {
    id   = "transfer-to-dead"
    next = "hang-up"
    transfer_contact_to_queue {}
    error {
      type = "QueueAtCapacity"
      next = "dead-full"
    }
    error {
      type = "NoMatchingError"
      next = "apologize"
    }
  }

  action {
    id   = "dead-full"
    next = "hang-up"
    message_participant {
      text = "The Queue of the Dead is full tonight, which is saying something. Call back after midnight; we will still be here, and so will you."
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
      text = "Something went wrong on our side. Please call back in a few minutes; you have the time."
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
