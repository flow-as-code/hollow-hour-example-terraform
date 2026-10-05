# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# hh-dead-queue-experience, the CUSTOMER_QUEUE flow a departed caller waits
# in: a Loop of reassurance that polls three times, then settles. No dequeue
# (there is no other queue for them) and no end block: a queue flow that
# ends leaves the caller in queue with nothing further from it, so the
# interruptible loop's error falls to the loop that keeps speaking.

resource "flowascode_contact_flow" "hh_dead_queue_experience" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-dead-queue-experience"
  type        = "CUSTOMER_QUEUE"
  description = "The Queue of the Dead: what a departed caller hears in queue. A loop of reassurance that polls a few times, then settles. No dequeue: there is no other queue for them."
  tags        = local.flow_tags

  action {
    id   = "keep-vigil"
    next = "settle-in"
    loop {
      loop_count = 3
    }
    condition {
      operator = "Equals"
      operands = ["ContinueLooping"]
      next     = "reassure"
    }
    condition {
      operator = "Equals"
      operands = ["DoneLooping"]
      next     = "settle-in"
    }
  }

  action {
    id = "reassure"
    message_participant_iteratively {
      interrupt_frequency_seconds = 30
      messages = [
        {
          text = "You are in the Queue of the Dead. A liaison will be with you; you have our word."
        },
        {
          text = "The living go first tonight, but nobody here is forgotten."
        },
      ]
    }
    condition {
      operator = "Equals"
      operands = ["MessagesInterrupted"]
      next     = "keep-vigil"
    }
    error {
      type = "NoMatchingError"
      next = "settle-in"
    }
  }

  action {
    id = "settle-in"
    message_participant_iteratively {
      messages = [
        {
          text = "Still with you. Rest if you can; the liaison knows you are waiting."
        },
      ]
    }
  }
}
