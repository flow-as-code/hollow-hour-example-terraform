# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

resource "flowascode_contact_flow" "hh_customer_whisper" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-customer-whisper"
  type        = "CUSTOMER_WHISPER"
  description = "What the caller hears as a district crew picks up. Reads contact attributes only."
  tags        = local.flow_tags

  action {
    id   = "connecting"
    next = "done"
    message_participant {
      text = "You are through to the $.Attributes.districtName crew. Stay with others and keep the lights on."
    }
    error {
      type = "NoMatchingError"
      next = "done"
    }
  }

  action {
    id = "done"
    end_flow_execution {}
  }
}
