# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# What a departed caller hears while the liaison has them on hold. One
# MessageParticipantIteratively and nothing else, as every hold flow here.
# Hooked as CustomerHold by hh-dead-line.

resource "flowascode_contact_flow" "hh_dead_hold" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-dead-hold"
  type        = "CUSTOMER_HOLD"
  description = "What a departed caller hears while the liaison has them on hold. One loop of prompts and nothing else, as every hold flow here."
  tags        = local.flow_tags

  action {
    id = "on-hold"
    message_participant_iteratively {
      messages = [
        {
          text = "Hold music is wasted on you, we know. Back shortly."
        },
      ]
    }
  }
}
