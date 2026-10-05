# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# What the crew member hears while the caller has them on hold. One
# MessageParticipantIteratively and nothing else, as every hold flow here.
# Hooked as AgentHold wherever the whispers are hooked, the dead line
# included: hh-dead-line sets gradeName to Departed before it queues.

resource "flowascode_contact_flow" "hh_agent_hold" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-agent-hold"
  type        = "AGENT_HOLD"
  description = "What the crew member hears while the caller has them on hold. One loop of prompts and nothing else. Reads contact attributes only."
  tags        = local.flow_tags

  action {
    id = "on-hold"
    message_participant_iteratively {
      messages = [
        {
          text = "Caller on hold. Grade $.Attributes.gradeName."
        },
      ]
    }
  }
}
