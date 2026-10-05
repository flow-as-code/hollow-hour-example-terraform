# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# What the caller hears while a crew member has them on hold. One
# MessageParticipantIteratively and nothing else: MessageParticipant and
# every terminal type are illegal in a hold flow, and a loop with no next
# ends it. Hooked as CustomerHold wherever the whispers are hooked.

resource "flowascode_contact_flow" "hh_customer_hold" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-customer-hold"
  type        = "CUSTOMER_HOLD"
  description = "What the caller hears while a crew member has them on hold. One loop of prompts and nothing else. Reads contact attributes only."
  tags        = local.flow_tags

  action {
    id = "on-hold"
    message_participant_iteratively {
      messages = [
        {
          text = "You are on hold with the $.Attributes.districtName crew. Keep the lights on."
        },
      ]
    }
  }
}
