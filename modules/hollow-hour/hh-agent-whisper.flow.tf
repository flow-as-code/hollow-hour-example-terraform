# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

resource "flowascode_contact_flow" "hh_agent_whisper" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-agent-whisper"
  type        = "AGENT_WHISPER"
  description = "What the crew hears before the caller joins: district, grade name and the advice already given. Reads contact attributes only."
  tags        = local.flow_tags

  action {
    id   = "brief-the-crew"
    next = "done"
    message_participant {
      text = "$.Attributes.districtName call. Grade: $.Attributes.gradeName. Advice given: $.Attributes.advice"
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
