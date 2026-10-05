# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# hh-offer-callback: the module that takes a callback for a caller who
# cannot wait. The caller's own number ($.CustomerEndpoint.Address, both
# errors wired, VERIFY.md 6.2), then a callback contact in
# queue:dispatch-overflow (tier decision 6: never a crew queue, static delays
# and attempts, VERIFY.md 16.2), worked by the next crew that comes free.
# Invoked by hh-district-<slug> after hours and at overflow-full, through its
# live alias (hh-offer-callback-release.tf), so its copy is shift-neutral: it
# runs mid-shift too. A refused create has its own copy; every path ends the
# module. This file holds the module alone, so flow-cli can read it; the
# version and alias the district flows bind are beside it.

resource "flowascode_contact_flow_module" "hh_offer_callback" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-offer-callback"
  description = "Takes a callback for a caller who cannot wait: the caller's own number, then a callback contact in the dispatch-overflow queue, worked by the next crew that comes free. Invoked by hh-district-<slug> after hours and when both crews are full."
  tags        = local.flow_tags

  settings = jsonencode({
    InputParameters  = []
    OutputParameters = []
    Transitions      = []
  })

  refs = {
    "queue:dispatch-overflow" = aws_connect_queue.shared["dispatch-overflow"].arn
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
    id   = "callback-taken"
    next = "done"
    message_participant {
      text = "You are on the list. A crew will call you back as soon as one comes free. Keep the lights on until then."
    }
    error {
      type = "NoMatchingError"
      next = "done"
    }
  }

  action {
    id   = "callback-refused"
    next = "done"
    message_participant {
      text = "We cannot take a callback right now; please call back in a few minutes."
    }
    error {
      type = "NoMatchingError"
      next = "done"
    }
  }

  action {
    id   = "cannot-ring-back"
    next = "done"
    message_participant {
      text = "We cannot ring you back at the number you are calling from, so please call us again from another phone."
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
