# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# What the spectral liaison hears before a departed caller joins. Static
# copy: the dead carry no grade. Hooked as AgentWhisper by hh-dead-line.

resource "flowascode_contact_flow" "hh_dead_whisper" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-dead-whisper"
  type        = "AGENT_WHISPER"
  description = "What the spectral liaison hears before a departed caller joins. Static copy; the dead carry no grade."
  tags        = local.flow_tags

  action {
    id   = "brief-the-liaison"
    next = "done"
    message_participant {
      text = "Spectral liaison call. Be patient; they have waited a long time."
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
