# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The front door: recording notice, the greeting module, caller lookup, the
# safety question, the plane check (a departed caller goes to hh-dead-line,
# and only after the safety question), the six-question keypad interview,
# the prank screen (never for a caller who said someone is hurt), the grade,
# the work order (UpdateContactData, named statically and described by the
# advice), and then the Lantern Crew (Hostile, Chorus) or the district menu
# (every other grade). Wherever the whispers are hooked, the holds are
# hooked too.
#
# check-caller, check-plane, check-injured-first, check-verdict and
# check-grade are Compares, and each carries next: Connect refuses a Compare
# without Transitions.NextAction (VERIFY.md).

resource "flowascode_contact_flow" "hh_hotline_main" {
  instance_id = aws_connect_instance.this.id
  name        = "hh-hotline-main"
  type        = "CONTACT_FLOW"
  description = "Hollow Hour Removal Co. front door: greeting, safety question, keypad interview, grade, district."
  tags        = local.flow_tags

  # Each reference key the actions use, bound to the resource it names. The
  # greeting is the live alias of var.season's module: the season switch.
  refs = {
    "flow:hh-agent-hold"         = flowascode_contact_flow.hh_agent_hold.arn
    "flow:hh-agent-whisper"      = flowascode_contact_flow.hh_agent_whisper.arn
    "flow:hh-customer-hold"      = flowascode_contact_flow.hh_customer_hold.arn
    "flow:hh-customer-whisper"   = flowascode_contact_flow.hh_customer_whisper.arn
    "flow:hh-dead-line"          = flowascode_contact_flow.hh_dead_line.arn
    "flow:hh-district-menu"      = flowascode_contact_flow.hh_district_menu.arn
    "lambda:caller-lookup"       = aws_connect_lambda_function_association.stub["caller-lookup"].function_arn
    "lambda:classify-apparition" = aws_connect_lambda_function_association.stub["classify-apparition"].function_arn
    "lambda:plane-check"         = aws_connect_lambda_function_association.stub["plane-check"].function_arn
    "lambda:prank-score"         = aws_connect_lambda_function_association.stub["prank-score"].function_arn
    "module:greeting@live"       = flowascode_contact_flow_module_alias.hh_greeting_live[var.season].arn
    "queue:dispatch-overflow"    = aws_connect_queue.shared["dispatch-overflow"].arn
    "queue:lantern-crew"         = aws_connect_queue.shared["lantern-crew"].arn
  }

  action {
    id   = "enable-logging"
    next = "set-voice"
    update_flow_logging_behavior {
      flow_logging_behavior = "Enabled"
    }
  }

  action {
    id   = "set-voice"
    next = "recording-notice"
    update_contact_text_to_speech_voice {
      text_to_speech_engine = "Neural"
      text_to_speech_voice  = "Matthew"
    }
    error {
      type = "NoMatchingError"
      next = "recording-notice"
    }
  }

  action {
    id   = "recording-notice"
    next = "start-recording"
    message_participant {
      text = "Hollow Hour Removal. Calls are recorded."
    }
    error {
      type = "NoMatchingError"
      next = "play-greeting"
    }
  }

  action {
    id   = "start-recording"
    next = "play-greeting"
    update_contact_recording_and_analytics_behavior {
      voice_behavior = {
        voice_recording_behavior = {
          recorded_participants = ["Agent", "Customer"]
        }
      }
    }
    error {
      type = "NoMatchingError"
      next = "play-greeting"
    }
    error {
      type = "ChannelMismatch"
      next = "play-greeting"
    }
  }

  action {
    id   = "play-greeting"
    next = "tag-season"
    invoke_flow_module {
      flow_module_id = "module:greeting@live"
    }
    error {
      type = "NoMatchingError"
      next = "fallback-greeting"
    }
  }

  action {
    id   = "tag-season"
    next = "look-up-caller"
    tag_contact {
      tags = {
        season = "$.Attributes.season"
      }
    }
    error {
      type = "NoMatchingError"
      next = "look-up-caller"
    }
  }

  action {
    id   = "look-up-caller"
    next = "check-caller"
    invoke_lambda_function {
      invocation_time_limit_seconds = 4
      invocation_type               = "SYNCHRONOUS"
      lambda_function_arn           = "lambda:caller-lookup"
      response_validation = {
        response_type = "JSON"
      }
    }
    error {
      type = "NoMatchingError"
      next = "ask-anyone-hurt"
    }
  }

  action {
    id   = "check-caller"
    next = "ask-anyone-hurt"
    compare {
      comparison_value = "$.External.status"
    }
    condition {
      operator = "Equals"
      operands = ["known"]
      next     = "remember-caller"
    }
    condition {
      operator = "Equals"
      operands = ["account"]
      next     = "remember-caller"
    }
    error {
      type = "NoMatchingCondition"
      next = "ask-anyone-hurt"
    }
  }

  action {
    id   = "remember-caller"
    next = "welcome-back"
    update_contact_attributes {
      attributes = {
        callerName   = "$.External.callerName"
        callerStatus = "$.External.status"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "ask-anyone-hurt"
    }
  }

  action {
    id   = "welcome-back"
    next = "ask-anyone-hurt"
    message_participant {
      text = "Welcome back, $.Attributes.callerName."
    }
    error {
      type = "NoMatchingError"
      next = "ask-anyone-hurt"
    }
  }

  action {
    id   = "ask-anyone-hurt"
    next = "emergency-advice"
    get_participant_input {
      input_time_limit_seconds = 8
      store_input              = "False"
      text                     = "Before anything else: is anyone hurt? If someone is hurt, press 1. If everyone is all right, press 2."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "emergency-advice"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "plane-check"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "emergency-advice"
    }
    error {
      type = "NoMatchingCondition"
      next = "emergency-advice"
    }
    error {
      type = "NoMatchingError"
      next = "emergency-advice"
    }
  }

  # Which side of the veil the caller is on. Only after the safety question:
  # the dead line is never reached without it. Numbers 555-0190 to 555-0199
  # are the departed (lambdas/plane-check).
  action {
    id   = "plane-check"
    next = "check-plane"
    invoke_lambda_function {
      invocation_time_limit_seconds = 4
      invocation_type               = "SYNCHRONOUS"
      lambda_function_arn           = "lambda:plane-check"
      response_validation = {
        response_type = "JSON"
      }
    }
    error {
      type = "NoMatchingError"
      next = "start-interview"
    }
  }

  action {
    id   = "check-plane"
    next = "start-interview"
    compare {
      comparison_value = "$.External.plane"
    }
    condition {
      operator = "Equals"
      operands = ["beyond"]
      next     = "to-dead-line"
    }
    error {
      type = "NoMatchingCondition"
      next = "start-interview"
    }
  }

  action {
    id   = "to-dead-line"
    next = "hang-up"
    transfer_to_flow {
      contact_flow_id = "flow:hh-dead-line"
    }
    error {
      type = "NoMatchingError"
      next = "start-interview"
    }
  }

  action {
    id   = "emergency-advice"
    next = "offer-end-or-continue"
    message_participant {
      text = "If anyone is hurt or in danger, please hang up now and call your local emergency number (911 in the US). We are a removal crew, not an emergency service."
    }
    error {
      type = "NoMatchingError"
      next = "offer-end-or-continue"
    }
  }

  action {
    id   = "offer-end-or-continue"
    next = "say-goodbye"
    get_participant_input {
      input_time_limit_seconds = 8
      store_input              = "False"
      text                     = "To end this call now, press 1. To stay on the line with us, press 2."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "say-goodbye"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "note-injury"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "say-goodbye"
    }
    error {
      type = "NoMatchingCondition"
      next = "say-goodbye"
    }
    error {
      type = "NoMatchingError"
      next = "say-goodbye"
    }
  }

  action {
    id   = "note-injury"
    next = "ask-can-see"
    update_flow_attributes {
      flow_attributes = {
        canSee = {
          value = "no"
        }
        coldSpot = {
          value = "no"
        }
        injured = {
          value = "yes"
        }
        movesObjects = {
          value = "no"
        }
        multiple = {
          value = "no"
        }
        sounds = {
          value = "no"
        }
        touched = {
          value = "no"
        }
      }
    }
    error {
      type = "NoMatchingError"
      next = "ask-can-see"
    }
  }

  action {
    id   = "start-interview"
    next = "ask-can-see"
    update_flow_attributes {
      flow_attributes = {
        canSee = {
          value = "no"
        }
        coldSpot = {
          value = "no"
        }
        injured = {
          value = "no"
        }
        movesObjects = {
          value = "no"
        }
        multiple = {
          value = "no"
        }
        sounds = {
          value = "no"
        }
        touched = {
          value = "no"
        }
      }
    }
    error {
      type = "NoMatchingError"
      next = "ask-can-see"
    }
  }

  action {
    id   = "ask-can-see"
    next = "ask-moves-objects"
    get_participant_input {
      input_time_limit_seconds = 8
      store_input              = "False"
      text                     = "Six quick questions, then we will send the right crew. Can you see it right now? Press 1 for yes, 2 for no."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "note-can-see"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "ask-moves-objects"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "ask-moves-objects"
    }
    error {
      type = "NoMatchingCondition"
      next = "ask-moves-objects"
    }
    error {
      type = "NoMatchingError"
      next = "ask-moves-objects"
    }
  }

  action {
    id   = "note-can-see"
    next = "ask-moves-objects"
    update_flow_attributes {
      flow_attributes = {
        canSee = {
          value = "yes"
        }
      }
    }
    error {
      type = "NoMatchingError"
      next = "ask-moves-objects"
    }
  }

  action {
    id   = "ask-moves-objects"
    next = "ask-cold-spot"
    get_participant_input {
      input_time_limit_seconds = 8
      store_input              = "False"
      text                     = "Has it moved anything? Press 1 for yes, 2 for no."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "note-moves-objects"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "ask-cold-spot"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "ask-cold-spot"
    }
    error {
      type = "NoMatchingCondition"
      next = "ask-cold-spot"
    }
    error {
      type = "NoMatchingError"
      next = "ask-cold-spot"
    }
  }

  action {
    id   = "note-moves-objects"
    next = "ask-cold-spot"
    update_flow_attributes {
      flow_attributes = {
        movesObjects = {
          value = "yes"
        }
      }
    }
    error {
      type = "NoMatchingError"
      next = "ask-cold-spot"
    }
  }

  action {
    id   = "ask-cold-spot"
    next = "ask-sounds"
    get_participant_input {
      input_time_limit_seconds = 8
      store_input              = "False"
      text                     = "Is there a cold spot where it happens? Press 1 for yes, 2 for no."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "note-cold-spot"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "ask-sounds"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "ask-sounds"
    }
    error {
      type = "NoMatchingCondition"
      next = "ask-sounds"
    }
    error {
      type = "NoMatchingError"
      next = "ask-sounds"
    }
  }

  action {
    id   = "note-cold-spot"
    next = "ask-sounds"
    update_flow_attributes {
      flow_attributes = {
        coldSpot = {
          value = "yes"
        }
      }
    }
    error {
      type = "NoMatchingError"
      next = "ask-sounds"
    }
  }

  action {
    id   = "ask-sounds"
    next = "ask-touched"
    get_participant_input {
      input_time_limit_seconds = 8
      store_input              = "False"
      text                     = "Have you heard it? Knocking, footsteps, humming, anything at all. Press 1 for yes, 2 for no."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "note-sounds"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "ask-touched"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "ask-touched"
    }
    error {
      type = "NoMatchingCondition"
      next = "ask-touched"
    }
    error {
      type = "NoMatchingError"
      next = "ask-touched"
    }
  }

  action {
    id   = "note-sounds"
    next = "ask-touched"
    update_flow_attributes {
      flow_attributes = {
        sounds = {
          value = "yes"
        }
      }
    }
    error {
      type = "NoMatchingError"
      next = "ask-touched"
    }
  }

  action {
    id   = "ask-touched"
    next = "ask-multiple"
    get_participant_input {
      input_time_limit_seconds = 8
      store_input              = "False"
      text                     = "Has it touched anyone? Press 1 for yes, 2 for no."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "note-touched"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "ask-multiple"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "ask-multiple"
    }
    error {
      type = "NoMatchingCondition"
      next = "ask-multiple"
    }
    error {
      type = "NoMatchingError"
      next = "ask-multiple"
    }
  }

  action {
    id   = "note-touched"
    next = "ask-multiple"
    update_flow_attributes {
      flow_attributes = {
        touched = {
          value = "yes"
        }
      }
    }
    error {
      type = "NoMatchingError"
      next = "ask-multiple"
    }
  }

  action {
    id   = "ask-multiple"
    next = "check-injured-first"
    get_participant_input {
      input_time_limit_seconds = 8
      store_input              = "False"
      text                     = "Last one. Could there be more than one of them? Press 1 for yes, 2 for no."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "note-multiple"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "check-injured-first"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "check-injured-first"
    }
    error {
      type = "NoMatchingCondition"
      next = "check-injured-first"
    }
    error {
      type = "NoMatchingError"
      next = "check-injured-first"
    }
  }

  action {
    id   = "note-multiple"
    next = "check-injured-first"
    update_flow_attributes {
      flow_attributes = {
        multiple = {
          value = "yes"
        }
      }
    }
    error {
      type = "NoMatchingError"
      next = "check-injured-first"
    }
  }

  # The prank screen. A caller who said someone is hurt skips it (safety
  # first); everyone else is scored, and a high verdict tags the contact and
  # asks kindly. Pressing 1 clears the tag and classifies; anything else is a
  # kind goodbye, so a wrong guess leaves no mark. Theo (555-0166) is the
  # known dare (lambdas/prank-score).
  action {
    id   = "check-injured-first"
    next = "prank-score"
    compare {
      comparison_value = "$.FlowAttributes.injured"
    }
    condition {
      operator = "Equals"
      operands = ["yes"]
      next     = "classify"
    }
    error {
      type = "NoMatchingCondition"
      next = "prank-score"
    }
  }

  action {
    id   = "prank-score"
    next = "check-verdict"
    invoke_lambda_function {
      invocation_time_limit_seconds = 4
      invocation_type               = "SYNCHRONOUS"
      lambda_function_arn           = "lambda:prank-score"
      lambda_invocation_attributes = {
        callerNumber = "$.CustomerEndpoint.Address"
        canSee       = "$.FlowAttributes.canSee"
        coldSpot     = "$.FlowAttributes.coldSpot"
        movesObjects = "$.FlowAttributes.movesObjects"
        multiple     = "$.FlowAttributes.multiple"
        sounds       = "$.FlowAttributes.sounds"
        touchedYou   = "$.FlowAttributes.touched"
      }
      response_validation = {
        response_type = "JSON"
      }
    }
    error {
      type = "NoMatchingError"
      next = "classify"
    }
  }

  action {
    id   = "check-verdict"
    next = "classify"
    compare {
      comparison_value = "$.External.verdict"
    }
    condition {
      operator = "Equals"
      operands = ["high"]
      next     = "tag-screen"
    }
    error {
      type = "NoMatchingCondition"
      next = "classify"
    }
  }

  action {
    id   = "tag-screen"
    next = "kind-check"
    tag_contact {
      tags = {
        screen = "prank-suspected"
      }
    }
    error {
      type = "NoMatchingError"
      next = "kind-check"
    }
  }

  action {
    id   = "kind-check"
    next = "dare-goodbye"
    get_participant_input {
      input_time_limit_seconds = 8
      store_input              = "False"
      text                     = "Some calls are dares, and that is all right. If this is really happening, press 1. Otherwise, press 2."
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "untag-screen"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "dare-goodbye"
    }
    error {
      type = "InputTimeLimitExceeded"
      next = "dare-goodbye"
    }
    error {
      type = "NoMatchingCondition"
      next = "dare-goodbye"
    }
    error {
      type = "NoMatchingError"
      next = "dare-goodbye"
    }
  }

  # The one way the tag leaves the flow set: if the untag itself fails, the
  # caller who said it is really happening goes on with the tag rather than
  # being hung up on. tests/flows.tftest.hcl holds that exception by name.
  action {
    id   = "untag-screen"
    next = "classify"
    untag_contact {
      tag_keys = ["screen"]
    }
    error {
      type = "NoMatchingError"
      next = "classify"
    }
  }

  action {
    id   = "dare-goodbye"
    next = "hang-up"
    message_participant {
      text = "Thanks for keeping us on our toes. Call back any time something goes bump."
    }
    error {
      type = "NoMatchingError"
      next = "hang-up"
    }
  }

  action {
    id   = "classify"
    next = "record-grade"
    invoke_lambda_function {
      invocation_time_limit_seconds = 4
      invocation_type               = "SYNCHRONOUS"
      lambda_function_arn           = "lambda:classify-apparition"
      lambda_invocation_attributes = {
        canSee       = "$.FlowAttributes.canSee"
        coldSpot     = "$.FlowAttributes.coldSpot"
        injured      = "$.FlowAttributes.injured"
        movesObjects = "$.FlowAttributes.movesObjects"
        multiple     = "$.FlowAttributes.multiple"
        sounds       = "$.FlowAttributes.sounds"
        touched      = "$.FlowAttributes.touched"
      }
      response_validation = {
        response_type = "JSON"
      }
    }
    error {
      type = "NoMatchingError"
      next = "note-ungraded"
    }
  }

  action {
    id   = "record-grade"
    next = "open-work-order"
    update_contact_attributes {
      attributes = {
        advice    = "$.External.advice"
        grade     = "$.External.grade"
        gradeName = "$.External.gradeName"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "note-ungraded"
    }
  }

  # Every graded call becomes a work order a crew can find in contact search
  # by its static name, with the advice as its description (VERIFY.md, D1).
  # The catch-all goes on to the advice: a refused update never costs the
  # caller what they were told.
  action {
    id   = "open-work-order"
    next = "share-advice"
    update_contact_data {
      description = "$.Attributes.advice"
      name        = "Hollow Hour work order"
    }
    error {
      type = "NoMatchingError"
      next = "share-advice"
    }
  }

  action {
    id   = "share-advice"
    next = "check-grade"
    message_participant {
      text = "Thank you. From what you describe, this is a $.Attributes.gradeName case. $.Attributes.advice"
    }
    error {
      type = "NoMatchingError"
      next = "check-grade"
    }
  }

  action {
    id   = "check-grade"
    next = "hand-to-dispatch"
    compare {
      comparison_value = "$.Attributes.grade"
    }
    condition {
      operator = "Equals"
      operands = ["1"]
      next     = "to-district-menu"
    }
    condition {
      operator = "Equals"
      operands = ["2"]
      next     = "to-district-menu"
    }
    condition {
      operator = "Equals"
      operands = ["3"]
      next     = "to-district-menu"
    }
    condition {
      operator = "Equals"
      operands = ["4"]
      next     = "send-to-lantern-crew"
    }
    condition {
      operator = "Equals"
      operands = ["5"]
      next     = "send-to-lantern-crew"
    }
    error {
      type = "NoMatchingCondition"
      next = "hand-to-dispatch"
    }
  }

  action {
    id   = "to-district-menu"
    next = "hang-up"
    transfer_to_flow {
      contact_flow_id = "flow:hh-district-menu"
    }
    error {
      type = "NoMatchingError"
      next = "hand-to-dispatch"
    }
  }

  action {
    id   = "send-to-lantern-crew"
    next = "note-lantern"
    message_participant {
      text = "This one is for the Lantern Crew. Stay somewhere bright and stay together while I connect you."
    }
    error {
      type = "NoMatchingError"
      next = "note-lantern"
    }
  }

  action {
    id   = "note-lantern"
    next = "set-lantern-customer-whisper"
    update_contact_attributes {
      attributes = {
        district     = "lantern-crew"
        districtName = "Lantern"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "set-lantern-customer-whisper"
    }
  }

  action {
    id   = "set-lantern-customer-whisper"
    next = "set-lantern-agent-whisper"
    update_contact_event_hooks {
      event_hooks = {
        CustomerWhisper = "$${cdref:flow:hh-customer-whisper}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-lantern-agent-whisper"
    }
  }

  action {
    id   = "set-lantern-agent-whisper"
    next = "set-lantern-customer-hold"
    update_contact_event_hooks {
      event_hooks = {
        AgentWhisper = "$${cdref:flow:hh-agent-whisper}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-lantern-customer-hold"
    }
  }

  action {
    id   = "set-lantern-customer-hold"
    next = "set-lantern-agent-hold"
    update_contact_event_hooks {
      event_hooks = {
        CustomerHold = "$${cdref:flow:hh-customer-hold}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-lantern-agent-hold"
    }
  }

  action {
    id   = "set-lantern-agent-hold"
    next = "set-lantern-queue"
    update_contact_event_hooks {
      event_hooks = {
        AgentHold = "$${cdref:flow:hh-agent-hold}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-lantern-queue"
    }
  }

  action {
    id   = "set-lantern-queue"
    next = "transfer-to-lantern"
    update_contact_target_queue {
      queue_id = "queue:lantern-crew"
    }
    error {
      type = "NoMatchingError"
      next = "hand-to-dispatch"
    }
  }

  action {
    id   = "transfer-to-lantern"
    next = "hang-up"
    transfer_contact_to_queue {}
    error {
      type = "QueueAtCapacity"
      next = "hand-to-dispatch"
    }
    error {
      type = "NoMatchingError"
      next = "apologize"
    }
  }

  # The dispatch fallback is the one chain an ungraded caller reaches (the
  # classifier failed, or the grade could not be recorded), and the agent
  # whisper and hold speak gradeName, so it gets a name on the way. A full
  # Lantern Crew keeps the grade it has.
  action {
    id   = "note-ungraded"
    next = "hand-to-dispatch"
    update_contact_attributes {
      attributes = {
        gradeName = "Ungraded"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "hand-to-dispatch"
    }
  }

  action {
    id   = "hand-to-dispatch"
    next = "note-dispatch"
    message_participant {
      text = "Let me put you through to a dispatcher."
    }
    error {
      type = "NoMatchingError"
      next = "note-dispatch"
    }
  }

  action {
    id   = "note-dispatch"
    next = "set-dispatch-customer-whisper"
    update_contact_attributes {
      attributes = {
        districtName = "Dispatch"
      }
      target_contact = "Current"
    }
    error {
      type = "NoMatchingError"
      next = "set-dispatch-customer-whisper"
    }
  }

  action {
    id   = "set-dispatch-customer-whisper"
    next = "set-dispatch-agent-whisper"
    update_contact_event_hooks {
      event_hooks = {
        CustomerWhisper = "$${cdref:flow:hh-customer-whisper}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dispatch-agent-whisper"
    }
  }

  action {
    id   = "set-dispatch-agent-whisper"
    next = "set-dispatch-customer-hold"
    update_contact_event_hooks {
      event_hooks = {
        AgentWhisper = "$${cdref:flow:hh-agent-whisper}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dispatch-customer-hold"
    }
  }

  action {
    id   = "set-dispatch-customer-hold"
    next = "set-dispatch-agent-hold"
    update_contact_event_hooks {
      event_hooks = {
        CustomerHold = "$${cdref:flow:hh-customer-hold}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dispatch-agent-hold"
    }
  }

  action {
    id   = "set-dispatch-agent-hold"
    next = "set-dispatch-queue"
    update_contact_event_hooks {
      event_hooks = {
        AgentHold = "$${cdref:flow:hh-agent-hold}"
      }
    }
    error {
      type = "NoMatchingError"
      next = "set-dispatch-queue"
    }
  }

  action {
    id   = "set-dispatch-queue"
    next = "transfer-to-dispatch"
    update_contact_target_queue {
      queue_id = "queue:dispatch-overflow"
    }
    error {
      type = "NoMatchingError"
      next = "apologize"
    }
  }

  action {
    id   = "transfer-to-dispatch"
    next = "hang-up"
    transfer_contact_to_queue {}
    error {
      type = "QueueAtCapacity"
      next = "lines-busy"
    }
    error {
      type = "NoMatchingError"
      next = "apologize"
    }
  }

  action {
    id   = "fallback-greeting"
    next = "look-up-caller"
    message_participant {
      text = "Hollow Hour Removal. If anyone is hurt or in danger, hang up and call your local emergency number (911 in the US)."
    }
    error {
      type = "NoMatchingError"
      next = "look-up-caller"
    }
  }

  action {
    id   = "say-goodbye"
    next = "hang-up"
    message_participant {
      text = "Take care of each other. Call us back once everyone is safe."
    }
    error {
      type = "NoMatchingError"
      next = "hang-up"
    }
  }

  action {
    id   = "lines-busy"
    next = "hang-up"
    message_participant {
      text = "Every crew is out on a call. Please call back in a few minutes."
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
      text = "Something went wrong on our side. Please call back in a few minutes."
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
