# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# hh-queue-experience-<slug>, the CUSTOMER_QUEUE flow each district's callers
# wait in: an ETA from lambda:crew-eta, and while the overflow sibling's crew
# has someone free, the offer to move there. One resource over
# local.district_flows (hh-district.tf), as the district flows are.
#
# check-moved, check-eta-band and hold are Compares, and each carries next:
# Connect refuses a Compare without Transitions.NextAction (VERIFY.md).
#
# The hold A/B split: on entry, pick-hold-variant (DistributeByPercentage,
# one NumberLessThan "51" branch and the remainder, so 50/50) sends each
# caller to a side that records holdVariant as a contact attribute and tags
# the contact with it, readable in contact search by tag (the
# TypeScript-first repository's VERIFY.md, DP1). hold is then a Compare on
# the attribute: recorded plays prompt:salt-line-tips (prompts.tf), the one
# recorded audio in the set, and falls back to the spoken tips if the
# prompt fails; anything else plays the spoken tips.
#
# The inline callback (tier decision 6): a customer queue flow cannot invoke
# a module, so when crew-eta says the wait is later the flow offers a
# callback itself, the caller's own number then a callback contact in
# queue:dispatch-overflow, and ends the taken callback with
# DisconnectParticipant, never EndFlowExecution, so nobody is both queued
# and holding a callback. Its errors go back to the hold.
#
# hold-spoken's error falls to settle-in, the loop that keeps speaking,
# never to done: a queue flow that ends leaves the caller in queue with
# nothing further from it. done stays for the paths that leave the queue.

resource "flowascode_contact_flow" "hh_queue_experience" {
  for_each = local.district_flows

  instance_id = aws_connect_instance.this.id
  name        = "hh-queue-experience-${each.key}"
  type        = "CUSTOMER_QUEUE"
  description = "Queue for the ${each.value.name} crew, offering a move to ${each.value.sibling.name} when that crew is free."
  tags        = local.flow_tags

  refs = {
    "lambda:crew-eta"                       = aws_connect_lambda_function_association.stub["crew-eta"].function_arn
    "prompt:salt-line-tips"                 = awscc_connect_prompt.salt_line_tips.prompt_arn
    "queue:dispatch-overflow"               = aws_connect_queue.shared["dispatch-overflow"].arn
    "queue:${each.value.sibling.slug}-crew" = aws_connect_queue.crew[each.value.sibling.slug].arn
  }

  action {
    id   = "check-moved"
    next = "pick-hold-variant"
    compare {
      comparison_value = "$.Attributes.moved"
    }
    condition {
      operator = "Equals"
      operands = ["true"]
      next     = "settle-in"
    }
    error {
      type = "NoMatchingCondition"
      next = "pick-hold-variant"
    }
  }

  action {
    id   = "pick-hold-variant"
    next = "note-recorded-variant"
    distribute_by_percentage {}
    condition {
      operator = "NumberLessThan"
      operands = ["51"]
      next     = "note-spoken-variant"
    }
    error {
      type = "NoMatchingCondition"
      next = "note-recorded-variant"
    }
  }

  action {
    id   = "note-spoken-variant"
    next = "tag-spoken-variant"
    update_contact_attributes {
      attributes = {
        holdVariant = "spoken"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "poll-crews"
    }
  }

  action {
    id   = "tag-spoken-variant"
    next = "poll-crews"
    tag_contact {
      tags = {
        holdVariant = "spoken"
      }
    }
    error {
      type = "NoMatchingError"
      next = "poll-crews"
    }
  }

  action {
    id   = "note-recorded-variant"
    next = "tag-recorded-variant"
    update_contact_attributes {
      attributes = {
        holdVariant = "recorded"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "poll-crews"
    }
  }

  action {
    id   = "tag-recorded-variant"
    next = "poll-crews"
    tag_contact {
      tags = {
        holdVariant = "recorded"
      }
    }
    error {
      type = "NoMatchingError"
      next = "poll-crews"
    }
  }

  action {
    id   = "poll-crews"
    next = "settle-in"
    loop {
      loop_count = 3
    }
    condition {
      operator = "Equals"
      operands = ["ContinueLooping"]
      next     = "check-eta"
    }
    condition {
      operator = "Equals"
      operands = ["DoneLooping"]
      next     = "settle-in"
    }
  }

  action {
    id   = "check-eta"
    next = "share-eta"
    invoke_lambda_function {
      invocation_time_limit_seconds = 3
      invocation_type               = "SYNCHRONOUS"
      lambda_function_arn           = "lambda:crew-eta"
      lambda_invocation_attributes = {
        district = each.key
      }
      response_validation = {
        response_type = "JSON"
      }
    }
    error {
      type = "NoMatchingError"
      next = "check-sibling"
    }
  }

  action {
    id   = "share-eta"
    next = "check-eta-band"
    message_participant {
      text = "The ${each.value.name} crew expects to be free in about $.External.etaMinutes minutes."
    }
    error {
      type = "NoMatchingError"
      next = "check-sibling"
    }
  }

  action {
    id   = "check-eta-band"
    next = "check-sibling"
    compare {
      comparison_value = "$.External.etaBand"
    }
    condition {
      operator = "Equals"
      operands = ["later"]
      next     = "offer-callback"
    }
    error {
      type = "NoMatchingCondition"
      next = "check-sibling"
    }
  }

  action {
    id   = "offer-callback"
    next = "check-sibling"
    get_participant_input {
      input_time_limit_seconds = 6
      store_input              = "False"
      text                     = "That is a long wait. For a callback from the next crew that comes free, press 1. To keep your place in line, press 2."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "set-callback-number"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "check-sibling"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "check-sibling"
    }
    error {
      type = "NoMatchingCondition"
      next = "check-sibling"
    }
    error {
      type = "NoMatchingError"
      next = "check-sibling"
    }
  }

  action {
    id   = "set-callback-number"
    next = "create-callback"
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
    next = "hold"
    message_participant {
      text = "We cannot ring you back at the number you are calling from, so we will keep your place in line."
    }
    error {
      type = "NoMatchingError"
      next = "hold"
    }
  }

  action {
    id   = "create-callback"
    next = "callback-taken"
    create_callback_contact {
      initial_call_delay_seconds  = 60
      maximum_connection_attempts = 2
      queue_id                    = "queue:dispatch-overflow"
      retry_delay_seconds         = 600
    }
    error {
      type = "NoMatchingError"
      next = "callback-refused"
    }
  }

  action {
    id   = "callback-refused"
    next = "hold"
    message_participant {
      text = "We cannot take a callback right now, so we will keep your place in line."
    }
    error {
      type = "NoMatchingError"
      next = "hold"
    }
  }

  action {
    id   = "callback-taken"
    next = "let-go"
    message_participant {
      text = "You are on the list. A crew will call you back as soon as one comes free. Keep the lights on until then."
    }
    error {
      type = "NoMatchingError"
      next = "let-go"
    }
  }

  action {
    id = "let-go"
    disconnect_participant {}
  }

  action {
    id   = "check-sibling"
    next = "hold"
    check_metric_data {
      metric_type = "NumberOfAgentsAvailable"
      queue_id    = "queue:${each.value.sibling.slug}-crew"
    }
    condition {
      operator = "NumberGreaterThan"
      operands = ["0"]
      next     = "offer-move"
    }
    error {
      type = "NoMatchingError"
      next = "hold"
    }
    error {
      type = "NoMatchingCondition"
      next = "hold"
    }
  }

  action {
    id   = "offer-move"
    next = "hold"
    get_participant_input {
      input_time_limit_seconds = 6
      store_input              = "False"
      text                     = "The ${each.value.sibling.name} crew has someone free right now. To move to them, press 1. To keep your place here, press 2."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "note-move"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "hold"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "hold"
    }
    error {
      type = "NoMatchingCondition"
      next = "hold"
    }
    error {
      type = "NoMatchingError"
      next = "hold"
    }
  }

  action {
    id   = "note-move"
    next = "moving"
    update_contact_attributes {
      attributes = {
        district     = each.value.sibling.slug
        districtName = each.value.sibling.name
        moved        = "true"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "hold"
    }
  }

  action {
    id = "moving"
    message_participant_iteratively {
      interrupt_frequency_seconds = 5
      messages = [
        {
          text = "Moving you to the ${each.value.sibling.name} crew now."
        },
      ]
    }
    condition {
      operator = "Equals"
      operands = ["MessagesInterrupted"]
      next     = "move-to-sibling"
    }
    error {
      type = "NoMatchingError"
      next = "stay-here"
    }
  }

  action {
    id   = "move-to-sibling"
    next = "done"
    dequeue_contact_and_transfer_to_queue {
      queue_id = "queue:${each.value.sibling.slug}-crew"
    }
    error {
      type = "QueueAtCapacity"
      next = "sibling-full"
    }
    error {
      type = "NoMatchingError"
      next = "stay-here"
    }
  }

  action {
    id   = "sibling-full"
    next = "stay-here"
    message_participant {
      text = "The ${each.value.sibling.name} crew just filled up. You still have your place with ${each.value.name}."
    }
    error {
      type = "NoMatchingError"
      next = "stay-here"
    }
  }

  action {
    id   = "stay-here"
    next = "hold"
    update_contact_attributes {
      attributes = {
        district     = each.key
        districtName = each.value.name
        moved        = "false"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "hold"
    }
  }

  action {
    id   = "hold"
    next = "hold-spoken"
    compare {
      comparison_value = "$.Attributes.holdVariant"
    }
    condition {
      operator = "Equals"
      operands = ["recorded"]
      next     = "hold-recorded"
    }
    error {
      type = "NoMatchingCondition"
      next = "hold-spoken"
    }
  }

  action {
    id = "hold-spoken"
    message_participant_iteratively {
      interrupt_frequency_seconds = 30
      messages = [
        {
          text = "While you wait: keep the lights on, keep pets close, and stay in a room with a door you can open."
        },
        {
          text = "A line of salt across the doorway never hurts. Nor does a cup of tea."
        },
      ]
    }
    condition {
      operator = "Equals"
      operands = ["MessagesInterrupted"]
      next     = "poll-crews"
    }
    error {
      type = "NoMatchingError"
      next = "settle-in"
    }
  }

  action {
    id = "hold-recorded"
    message_participant_iteratively {
      interrupt_frequency_seconds = 30
      messages = [
        {
          prompt_id = "prompt:salt-line-tips"
        },
      ]
    }
    condition {
      operator = "Equals"
      operands = ["MessagesInterrupted"]
      next     = "poll-crews"
    }
    error {
      type = "NoMatchingError"
      next = "hold-spoken"
    }
  }

  action {
    id = "settle-in"
    message_participant_iteratively {
      messages = [
        {
          text = "You are still in line for the $.Attributes.districtName crew, and they know you are waiting."
        },
        {
          text = "Keep the lights on and stay with others. A crew member will be with you soon."
        },
      ]
    }
  }

  action {
    id = "done"
    end_flow_execution {}
  }
}
