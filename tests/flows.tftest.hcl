# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# What the flows read to, checked on the FlowDocs the real flowascode provider
# computes at plan time (its flowdoc attribute: the document with reference
# tokens in place). aws is mocked, so nothing is created and no credential is
# needed; flowascode is real but only plans, and planning makes no AWS call.
#
# Holds: every Compare carries next (Connect refuses one without
# Transitions.NextAction); every reference a flow makes is bound in its refs
# and every refs key is used; no ARN is written into a flow; one district
# flow and one queue-experience flow per district, and a menu key each; the
# queue cap per environment; every flow and module carries the tags; the
# flow log group is optional; the closed hours and the recording storage
# have the settled shape; the variables refuse a broken overflow and values
# AWS would refuse at apply; the prompt's bucket, object and tags. The Tier 2
# runs (dead_line, holds, hooks, prank_screen, callback_number, callbacks,
# hold_ab) hold the invariants the TypeScript-first repository's
# tests/flows.test.ts holds, on the walks fixtures/walks computes.
# tests/environments.tftest.hcl compares the profiles.

mock_provider "aws" {
  # Shapes the aws provider validates: an IAM policy that parses and ARNs
  # that parse. 000000000000 and the zero UUID are placeholders. Everything
  # else is generated.
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_connect_instance" {
    defaults = { arn = "arn:aws:connect:us-east-1:000000000000:instance/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::000000000000:role/mock" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:000000000000:function:mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:000000000000:log-group:mock" }
  }
}

# awscc is mocked too: the prompt is never created, and the queue flows bind
# prompt:salt-line-tips to the ARN shape a prompt carries.
mock_provider "awscc" {
  mock_resource "awscc_connect_prompt" {
    defaults = { prompt_arn = "arn:aws:connect:us-east-1:000000000000:instance/00000000-0000-0000-0000-000000000000/prompt/00000000-0000-0000-0000-000000000000" }
  }
}

provider "flowascode" {
  region                      = "us-east-1"
  access_key                  = "offline"
  secret_key                  = "offline"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

variables {
  environment = "prod"
  hours       = "night_shift"
  season      = "standard"
}

run "prod" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  assert {
    condition = toset(keys(output.flowdocs)) == toset([
      "hh-agent-hold",
      "hh-agent-whisper",
      "hh-customer-hold",
      "hh-customer-whisper",
      "hh-dead-hold",
      "hh-dead-line",
      "hh-dead-queue-experience",
      "hh-dead-whisper",
      "hh-district-graveyard-hill",
      "hh-district-harborside",
      "hh-district-menu",
      "hh-district-old-town",
      "hh-greeting-halloween",
      "hh-greeting-standard",
      "hh-hotline-main",
      "hh-offer-callback",
      "hh-queue-experience-graveyard-hill",
      "hh-queue-experience-harborside",
      "hh-queue-experience-old-town",
    ])
    error_message = "The module deploys the ten Tier 1 flows, the six Tier 2 flows, the callback module and the two greeting modules, named as in the TypeScript-first repository."
  }

  assert {
    condition = alltrue(flatten([
      for name, doc in output.flowdocs : [
        for a in jsondecode(doc).content.Actions :
        try(a.Transitions.NextAction, "") != "" if a.Type == "Compare"
      ]
    ]))
    error_message = "A Compare has no next. Connect refuses a Compare without Transitions.NextAction (VERIFY.md, C1): set next to its NoMatchingCondition target."
  }

  assert {
    condition = length(flatten([
      for name, doc in output.flowdocs : [
        for a in jsondecode(doc).content.Actions : a if a.Type == "Compare"
      ]
    ])) == 14
    error_message = "Expected fourteen Compares (check-caller, check-plane, check-injured-first, check-verdict, check-grade, and check-moved, check-eta-band and hold per district); the Compare check above would pass vacuously on none."
  }

  assert {
    condition = alltrue([
      for name, refs in output.flow_refs :
      toset(keys(refs)) == toset([
        for r in jsondecode(output.flowdocs[name]).refs :
        trimsuffix(trimprefix(r.token, "$${cdref:"), "}")
      ])
    ])
    error_message = "A flow's refs and the references its actions make differ: every reference key an action uses is bound in refs, and every refs key is used."
  }

  assert {
    condition     = alltrue([for name, doc in output.flowdocs : !strcontains(jsondecode(doc).content == null ? "" : jsonencode(jsondecode(doc).content), "arn:")])
    error_message = "A flow's content holds an ARN. References are tokens bound through refs, never literal ARNs."
  }

  assert {
    condition     = keys(aws_connect_queue.crew) == ["graveyard-hill", "harborside", "old-town"]
    error_message = "One crew queue per district."
  }

  assert {
    condition     = keys(flowascode_contact_flow.hh_district) == keys(aws_connect_queue.crew) && keys(flowascode_contact_flow.hh_queue_experience) == keys(aws_connect_queue.crew)
    error_message = "One district flow and one queue-experience flow per district."
  }

  assert {
    condition     = output.district_hours == { "old-town" = "night_shift", "harborside" = "night_shift", "graveyard-hill" = "night_shift" }
    error_message = "Every district crew keeps the environment's hours profile unless its entry names another."
  }

  assert {
    condition     = jsondecode(output.flowdocs["hh-district-menu"]).content.Actions[0].Parameters.Text == "Where are you calling from? For Old Town, press 1. For Harborside, press 2. For Graveyard Hill, press 3."
    error_message = "The menu prompt names each district with its key, in var.districts order."
  }

  assert {
    condition = [
      for c in jsondecode(output.flowdocs["hh-district-menu"]).content.Actions[0].Transitions.Conditions :
      "${c.Condition.Operands[0]}:${c.NextAction}"
    ] == ["1:route-old-town", "2:route-harborside", "3:route-graveyard-hill"]
    error_message = "Menu key n routes to the nth district."
  }

  assert {
    condition     = aws_connect_queue.crew["old-town"].max_contacts == 25 && aws_connect_queue.shared["dispatch-overflow"].max_contacts == 25
    error_message = "prod queues hold 25 contacts."
  }

  # flowascode has no default_tags, so the module tags each flow and module.
  assert {
    condition = alltrue(concat(
      [for f in concat(
        [flowascode_contact_flow.hh_hotline_main, flowascode_contact_flow.hh_district_menu, flowascode_contact_flow.hh_agent_whisper, flowascode_contact_flow.hh_customer_whisper],
        [flowascode_contact_flow.hh_customer_hold, flowascode_contact_flow.hh_agent_hold, flowascode_contact_flow.hh_dead_line, flowascode_contact_flow.hh_dead_whisper, flowascode_contact_flow.hh_dead_hold, flowascode_contact_flow.hh_dead_queue_experience],
        values(flowascode_contact_flow.hh_district),
        values(flowascode_contact_flow.hh_queue_experience),
      ) : f.tags == tomap({ "hollow-hour-example-terraform" = "true", "environment" = "prod" })],
      [for m in values(flowascode_contact_flow_module.hh_greeting) : m.tags == tomap({ "hollow-hour-example-terraform" = "true", "environment" = "prod" })],
      [flowascode_contact_flow_module.hh_offer_callback.tags == tomap({ "hollow-hour-example-terraform" = "true", "environment" = "prod" })],
    ))
    error_message = "Every flow and module carries the hollow-hour-example-terraform and environment tags."
  }

  # awscc has no default_tags, so the prompt carries the same two tags
  # itself, as a set of {key, value} objects.
  assert {
    condition     = tomap({ for t in awscc_connect_prompt.salt_line_tips.tags : t.key => t.value }) == tomap({ "hollow-hour-example-terraform" = "true", "environment" = "prod" })
    error_message = "The prompt's tags are not exactly the two tags the aws provider puts on everything else."
  }

  # The recorded prompt (prompts.tf): a private SSE-S3 bucket with no
  # policy, the committed wav as its one object under a key that carries the
  # file's MD5, and the Connect prompt made from that object on this
  # instance, named hh-tf-<environment>-salt-line-tips.
  assert {
    condition = (
      startswith(aws_s3_bucket.prompts.bucket, "hh-tf-prod-prompts-") &&
      tolist(tolist(aws_s3_bucket_server_side_encryption_configuration.prompts.rule)[0].apply_server_side_encryption_by_default)[0].sse_algorithm == "AES256" &&
      aws_s3_bucket_public_access_block.prompts.block_public_acls && aws_s3_bucket_public_access_block.prompts.block_public_policy &&
      aws_s3_bucket_public_access_block.prompts.ignore_public_acls && aws_s3_bucket_public_access_block.prompts.restrict_public_buckets &&
      tolist(aws_s3_bucket_ownership_controls.prompts.rule)[0].object_ownership == "BucketOwnerEnforced" &&
      aws_s3_object.salt_line_tips.key == "salt-line-tips-${filemd5("../modules/hollow-hour/prompts/salt-line-tips.wav")}.wav" &&
      aws_s3_object.salt_line_tips.source_hash == filemd5("../modules/hollow-hour/prompts/salt-line-tips.wav") &&
      aws_s3_object.salt_line_tips.content_type == "audio/wav" &&
      awscc_connect_prompt.salt_line_tips.name == "hh-tf-prod-salt-line-tips" &&
      awscc_connect_prompt.salt_line_tips.instance_arn == aws_connect_instance.this.arn &&
      awscc_connect_prompt.salt_line_tips.s3_uri == "s3://${aws_s3_object.salt_line_tips.bucket}/${aws_s3_object.salt_line_tips.key}"
    )
    error_message = "The prompt audio lives in a private SSE-S3 bucket named hh-tf-<environment>-prompts-<suffix>, as one object keyed on the wav's MD5, and the prompt is made from that object on this instance."
  }

  # The committed audio is a RIFF wav (the shape Connect recommends for a
  # prompt; the TypeScript-first repository's VERIFY.md, P1) with the copy
  # it was synthesized from beside it, and it is the object's source.
  assert {
    condition = (
      endswith(aws_s3_object.salt_line_tips.source, "/prompts/salt-line-tips.wav") &&
      startswith(filebase64("../modules/hollow-hour/prompts/salt-line-tips.wav"), "UklGR") &&
      length(file("../modules/hollow-hour/prompts/salt-line-tips.txt")) > 40
    )
    error_message = "The object's source is not prompts/salt-line-tips.wav, the wav is not RIFF, or prompts/salt-line-tips.txt (the copy it was synthesized from) is missing."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.connect_flow_logs) == 1 && aws_cloudwatch_log_group.connect_flow_logs[0].retention_in_days == 14
    error_message = "By default the module creates the flow log group, with 14 days of retention."
  }

  # The closed hours (the TypeScript-first repository's hours:closed, VERIFY.md
  # HC1): open one minute a week and nothing else, read by no flow.
  assert {
    condition = (
      aws_connect_hours_of_operation.closed.name == "hh-tf-prod-closed" &&
      [for c in aws_connect_hours_of_operation.closed.config : "${c.day} ${tolist(c.start_time)[0].hours}:${tolist(c.start_time)[0].minutes} ${tolist(c.end_time)[0].hours}:${tolist(c.end_time)[0].minutes}"] == ["SUNDAY 3:0 3:1"] &&
      !anytrue([for name, refs in output.flow_refs : contains(keys(refs), "hours:closed")])
    )
    error_message = "The closed hours are hh-tf-<environment>-closed, open Sunday 03:00 to 03:01 and nothing else, and no flow binds them: they exist for scenario S4's substitution."
  }

  # Recording storage (tier decision 5; the TypeScript-first repository's
  # VERIFY.md RS1): a private SSE-S3 bucket under the amazon-connect- prefix,
  # a 30-day expiry, no customer key, as the instance's CALL_RECORDINGS store.
  assert {
    condition = (
      startswith(aws_s3_bucket.recordings.bucket, "amazon-connect-hh-tf-prod-recordings-") &&
      tolist(tolist(aws_s3_bucket_server_side_encryption_configuration.recordings.rule)[0].apply_server_side_encryption_by_default)[0].sse_algorithm == "AES256" &&
      aws_s3_bucket_public_access_block.recordings.block_public_acls && aws_s3_bucket_public_access_block.recordings.block_public_policy &&
      aws_s3_bucket_public_access_block.recordings.ignore_public_acls && aws_s3_bucket_public_access_block.recordings.restrict_public_buckets &&
      tolist(aws_s3_bucket_lifecycle_configuration.recordings.rule)[0].status == "Enabled" &&
      tolist(tolist(aws_s3_bucket_lifecycle_configuration.recordings.rule)[0].expiration)[0].days == 30 &&
      aws_connect_instance_storage_config.call_recordings.resource_type == "CALL_RECORDINGS" &&
      tolist(aws_connect_instance_storage_config.call_recordings.storage_config)[0].storage_type == "S3" &&
      length(tolist(tolist(aws_connect_instance_storage_config.call_recordings.storage_config)[0].s3_config)[0].encryption_config) == 0
    )
    error_message = "Call recordings go to a private SSE-S3 bucket named amazon-connect-<name prefix>-recordings-<suffix>, expired after 30 days, with no customer managed key (tier decision 5)."
  }
}

# Tier 2, on the walks tests/fixtures/walks computes over the planned
# FlowDocs (prod's values; every profile has the same content). Each run
# mirrors the TypeScript-first repository's tests/flows.test.ts.

# hh-dead-line: the welcome precedes the recording block, which records the
# Agent alone and has no error branch; the routing adjustment is static,
# negative, without a priority, and set before the target queue and the
# transfer; the four hooks are set, one per block, on a path from the start;
# the dead never close; the transfer wires both errors.
run "dead_line" {
  command = plan

  module {
    source = "./fixtures/walks"
  }

  assert {
    condition     = output.converged
    error_message = "A walk did not settle within 128 steps; fixtures/reach needs another doubling."
  }

  assert {
    condition = (
      output.dead.start == "dead-welcome" &&
      output.dead.welcome_type == "MessageParticipant" &&
      strcontains(output.dead.welcome_text, "recorded") &&
      output.dead.welcome_next == "record-agent-only" &&
      !contains(output.reach.dead_without_welcome, "record-agent-only")
    )
    error_message = "The dead line starts with a welcome that says the call is recorded, and the recording block is never reached without it (VERIFY 16.4)."
  }

  assert {
    condition     = output.dead.recording_type == "UpdateContactRecordingBehavior" && tolist(output.dead.recorded) == tolist(["Agent"]) && output.dead.recording_errs == 0
    error_message = "record-agent-only records exactly the Agent and has no error branch (catalog rule 37)."
  }

  assert {
    condition = (
      output.dead.patience_type == "UpdateContactRoutingBehavior" &&
      can(regex("^-[0-9]+$", output.dead.adjustment)) &&
      !output.dead.has_priority &&
      !contains(output.reach.dead_without_patience, "set-dead-queue") &&
      !contains(output.reach.dead_without_patience, "transfer-to-dead") &&
      contains(output.reach.dead_all, "transfer-to-dead")
    )
    error_message = "set-patience is a static negative adjustment with no priority, reached before the target queue and the transfer (VERIFY 16.5)."
  }

  assert {
    condition = (
      alltrue([for h in output.dead.hooks : length(keys(h.hooks)) == 1]) &&
      merge([for h in output.dead.hooks : h.hooks]...) == {
        AgentWhisper  = "$${cdref:flow:hh-dead-whisper}"
        CustomerHold  = "$${cdref:flow:hh-dead-hold}"
        CustomerQueue = "$${cdref:flow:hh-dead-queue-experience}"
        AgentHold     = "$${cdref:flow:hh-agent-hold}"
      }
    )
    error_message = "The dead line sets AgentWhisper, CustomerHold, CustomerQueue and AgentHold to its own flows, one hook per block, on a path from the start (VERIFY 16.3)."
  }

  assert {
    condition     = output.dead.hours_id == "$${cdref:hours:the-dead}" && output.dead.hours_branches == toset(["set-dead-queue"])
    error_message = "The dead never close: both branches of check-dead-hours continue to the queue."
  }

  assert {
    condition     = output.dead.queue_id == "$${cdref:queue:the-dead}" && tolist(output.dead.transfer_errors) == tolist(["NoMatchingError", "QueueAtCapacity"])
    error_message = "The dead line queues to queue:the-dead with QueueAtCapacity and NoMatchingError wired."
  }

  assert {
    condition     = output.hold_flows["hh-dead-hold"].type == "CUSTOMER_HOLD" && tomap(output.types["hh-dead-whisper"]) == tomap({ "brief-the-liaison" = "MessageParticipant", "done" = "EndFlowExecution" })
    error_message = "hh-dead-hold is a hold flow and hh-dead-whisper one message then an end."
  }

  assert {
    condition = (
      contains(keys(output.types["hh-dead-queue-experience"]), "keep-vigil") &&
      output.types["hh-dead-queue-experience"]["keep-vigil"] == "Loop" &&
      !contains(values(output.types["hh-dead-queue-experience"]), "DequeueContactAndTransferToQueue") &&
      !contains(values(output.types["hh-dead-queue-experience"]), "EndFlowExecution") &&
      !contains(values(output.types["hh-dead-queue-experience"]), "TransferContactToQueue")
    )
    error_message = "The Queue of the Dead loops and reassures, never dequeues, and never ends: a queue flow that ends leaves the caller in queue with nothing further."
  }
}

# The plane check: only after the safety question, and the dead line is
# never reached without it.
run "plane_check" {
  command = plan

  module {
    source = "./fixtures/walks"
  }

  assert {
    condition = (
      tolist(output.plane.after_safety_no) == tolist(["plane-check"]) &&
      output.plane.lambda == "$${cdref:lambda:plane-check}" &&
      output.plane.compares == "$.External.plane" &&
      tolist(output.plane.beyond) == tolist(["to-dead-line"]) &&
      output.plane.otherwise == "start-interview" &&
      output.plane.to_flow == "$${cdref:flow:hh-dead-line}"
    )
    error_message = "A no to the safety question runs plane-check; beyond goes to hh-dead-line, anything else to the interview."
  }

  assert {
    condition     = contains(output.reach.dead_line, "to-dead-line") && !contains(output.reach.dead_line_without_safety, "to-dead-line")
    error_message = "The dead line is reachable, and no path reaches it without ask-anyone-hurt."
  }
}

# Each hold flow is one MessageParticipantIteratively and nothing else: no
# next, no branch, no interrupt. hh-customer-hold names the crew; hh-agent-hold
# names the grade.
run "holds" {
  command = plan

  module {
    source = "./fixtures/walks"
  }

  assert {
    condition     = toset(keys(output.hold_flows)) == toset(["hh-agent-hold", "hh-customer-hold", "hh-dead-hold"])
    error_message = "The set holds exactly the customer, agent and dead hold flows."
  }

  assert {
    condition = alltrue([
      for name, h in output.hold_flows :
      h.actions == 1 && h.start == h.first && h.first_of == "MessageParticipantIteratively" && !h.has_next && h.branches == 0 && !h.interrupt
    ])
    error_message = "A hold flow is one MessageParticipantIteratively with no next, no condition or error branch and no interrupt: MessageParticipant and every terminal type are illegal there, and a loop with no next ends the flow."
  }

  assert {
    condition = (
      output.hold_flows["hh-customer-hold"].type == "CUSTOMER_HOLD" && strcontains(output.hold_flows["hh-customer-hold"].text, "$.Attributes.districtName") &&
      output.hold_flows["hh-agent-hold"].type == "AGENT_HOLD" && strcontains(output.hold_flows["hh-agent-hold"].text, "$.Attributes.gradeName")
    )
    error_message = "hh-customer-hold names the crew the caller is with; hh-agent-hold names the grade."
  }
}

# Hooks: one per block; a hooked flow is in the set and never references
# the flow that hooks it back (a cycle in the resource graph, VERIFY 16.3);
# wherever CustomerWhisper is set, AgentWhisper, CustomerHold and AgentHold
# follow in the same chain, so no path that reaches an agent gets Connect's
# default hold; no Wait anywhere.
run "hooks" {
  command = plan

  module {
    source = "./fixtures/walks"
  }

  assert {
    condition     = alltrue([for b in output.hook_blocks : length(b.hooks) == 1])
    error_message = "An UpdateContactEventHooks block sets more than one hook; each hook gets a block of its own (VERIFY 16.3)."
  }

  assert {
    condition = alltrue(flatten([
      for b in output.hook_blocks : [
        for target in b.targets :
        target != b.flow && contains(keys(output.refs), target) && !contains(output.refs[target], "$${cdref:flow:${b.flow}}")
      ]
    ]))
    error_message = "A hooked flow hooks itself, is not in the set, or references the flow that hooks it back."
  }

  assert {
    condition     = length(output.hook_blocks) == 46
    error_message = "Expected 46 hook blocks (ten per district flow: five, the overflow queue hook, and four for dispatch; four in the menu; four in each of the hotline's two chains; four in the dead line); the hook checks above would pass vacuously on none."
  }

  assert {
    condition     = alltrue([for c in output.whisper_chains : tolist(c.hooks) == tolist(["CustomerWhisper", "AgentWhisper", "CustomerHold", "AgentHold"])])
    error_message = "A chain sets CustomerWhisper without AgentWhisper, CustomerHold and AgentHold following it block by block (decided 2026-10-05: the whisper and hold hooks travel together)."
  }

  assert {
    condition     = length(output.whisper_chains) == 9
    error_message = "Expected nine CustomerWhisper chains (two per district flow, two in the hotline, one in the menu)."
  }

  assert {
    condition     = length(output.waits) == 0
    error_message = "A flow holds a Wait. Wait is chat only (VERIFY 16.1), and every flow here is voice."
  }
}

# The prank screen: after the last question, never for a caller who said
# someone is hurt, a high verdict tags the contact and asks kindly, and every
# path through the tag untags it or ends the call, with one held exception.
run "prank_screen" {
  command = plan

  module {
    source = "./fixtures/walks"
  }

  assert {
    condition = (
      tolist(output.prank.after_last_question) == tolist(["check-injured-first"]) &&
      output.prank.compares == "$.FlowAttributes.injured" &&
      tolist(output.prank.injured_yes) == tolist(["classify"]) &&
      tolist(output.prank.injured_no) == tolist(["prank-score"]) &&
      output.prank.score_lambda == "$${cdref:lambda:prank-score}" &&
      tolist(output.prank.score_inputs) == tolist(["callerNumber", "canSee", "coldSpot", "movesObjects", "multiple", "sounds", "touchedYou"]) &&
      tolist(output.prank.verdict_high) == tolist(["tag-screen"]) &&
      tomap(output.prank.tag) == tomap({ screen = "prank-suspected" })
    )
    error_message = "After the last question an injured caller goes straight to classify; everyone else is scored with the answers and the number, and a high verdict tags screen=prank-suspected."
  }

  assert {
    condition = (
      tomap(output.prank.kind_keys) == tomap({ "1" = "untag-screen", "2" = "dare-goodbye" }) &&
      tolist(output.prank.kind_default) == tolist(["dare-goodbye"]) &&
      output.prank.untag_type == "UntagContact" && tolist(output.prank.untag_keys) == tolist(["screen"]) && output.prank.untag_next == "classify" &&
      output.prank.goodbye_next == "hang-up" && output.types["hh-hotline-main"]["hang-up"] == "DisconnectParticipant" &&
      strcontains(output.prank.goodbye_text, "Thanks") && !strcontains(lower(output.prank.goodbye_text), "prank")
    )
    error_message = "Pressing 1 clears the tag and classifies; 2, a timeout or an error is a kind goodbye and a hang-up, never an accusation."
  }

  # Injured callers: the only blocks that set the injured attribute are
  # note-injury (yes) and start-interview (no); every path from the advice to
  # the Compare passes note-injury and never start-interview; with the
  # Compare then taking its yes branch, prank-score is unreachable. An
  # uninjured caller is screened.
  assert {
    condition = (
      tomap(output.prank.injured_setters) == tomap({ "note-injury" = "yes", "start-interview" = "no" }) &&
      !contains(output.reach.injured_without_note, "check-injured-first") &&
      !contains(output.reach.injured_caller, "start-interview") &&
      !contains(output.reach.injured_caller, "prank-score") &&
      contains(output.reach.uninjured_caller, "prank-score")
    )
    error_message = "A caller who said someone is hurt is never screened: no path from the emergency advice reaches prank-score with injured tracked, while an uninjured caller does reach it."
  }

  # From tag-screen, stopping at untag-screen and the disconnect, nothing
  # reachable leaves the flow: no transfer, module, end or dequeue.
  assert {
    condition = [
      for id in output.reach.screen_tag : id
      if contains(["TransferToFlow", "TransferContactToQueue", "InvokeFlowModule", "EndFlowExecution", "DequeueContactAndTransferToQueue"], output.types["hh-hotline-main"][id])
    ] == []
    error_message = "A path through the screen tag leaves the flow with the tag set: every path must untag it or end the call."
  }

  # The held exception: a failed untag-screen goes on to classify with the
  # tag set, because hanging up on a caller who said it is really happening
  # is the worse outcome, and what it then reaches is exactly the three
  # transfers.
  assert {
    condition = tolist(output.prank.untag_errors) == tolist(["classify"]) && toset([
      for id in output.reach.after_failed_untag : id
      if contains(["TransferToFlow", "TransferContactToQueue", "InvokeFlowModule", "EndFlowExecution", "DequeueContactAndTransferToQueue"], output.types["hh-hotline-main"][id])
    ]) == toset(["to-district-menu", "transfer-to-lantern", "transfer-to-dispatch"])
    error_message = "A failed untag-screen is the one way the tag leaves the flow, through classify to the three transfers and nothing else."
  }
}

# Wherever the callback number is set, it is the caller's own and both
# errors are wired (VERIFY 6.2); in the dead line both say so and rejoin.
run "callback_number" {
  command = plan

  module {
    source = "./fixtures/walks"
  }

  assert {
    condition = toset([for s in output.callback_setters : "${s.flow}#${s.id}"]) == toset([
      "hh-dead-line#set-callback-number",
      "hh-offer-callback#set-callback-number",
      "hh-queue-experience-graveyard-hill#set-callback-number",
      "hh-queue-experience-harborside#set-callback-number",
      "hh-queue-experience-old-town#set-callback-number",
    ])
    error_message = "The callback number is set in the dead line, the callback module and each queue flow, and nowhere else; the checks below would pass vacuously on none."
  }

  assert {
    condition     = alltrue([for s in output.callback_setters : s.number == "$.CustomerEndpoint.Address" && tolist(s.errors) == tolist(["CallbackNumberNotDialable", "InvalidCallbackNumber"])])
    error_message = "An UpdateContactCallbackNumber sets a number other than $.CustomerEndpoint.Address, or leaves CallbackNumberNotDialable or InvalidCallbackNumber unwired."
  }

  assert {
    condition = (
      jsonencode([for s in output.callback_setters : s.targets if s.flow == "hh-dead-line"]) == jsonencode([["cannot-ring-back"]]) &&
      output.types["hh-dead-line"]["cannot-ring-back"] == "MessageParticipant"
    )
    error_message = "In the dead line both callback-number errors go to cannot-ring-back, which rejoins the flow."
  }
}

# Callbacks (tier decision 6; the TypeScript-first repository's VERIFY.md
# 16.2, 16.12, CB1): every CreateCallbackContact names queue:dispatch-overflow
# explicitly, never a crew queue and never the current queue by omission,
# with static counts; none, and no invoke of the callback module, is
# reachable from lines-busy; the module's shape; the district offer after
# hours and at overflow-full through the live alias, with a sign-off before
# the hang-up and lines-busy left plain; the queue flow's inline callback,
# errors back to the hold, ending in DisconnectParticipant.
run "callbacks" {
  command = plan

  module {
    source = "./fixtures/walks"
  }

  assert {
    condition     = output.converged
    error_message = "A walk did not settle within 128 steps; fixtures/reach needs another doubling."
  }

  assert {
    condition = toset([for c in output.callbacks : "${c.flow}#${c.id}"]) == toset([
      "hh-offer-callback#create-callback",
      "hh-queue-experience-graveyard-hill#create-callback",
      "hh-queue-experience-harborside#create-callback",
      "hh-queue-experience-old-town#create-callback",
    ])
    error_message = "Callbacks are created in the module and once per queue flow, and nowhere else; the checks below would pass vacuously on none."
  }

  assert {
    condition     = alltrue([for c in output.callbacks : c.queue == "$${cdref:queue:dispatch-overflow}"])
    error_message = "A CreateCallbackContact names no queue (the contact's current queue, a crew queue at its cap) or a queue other than queue:dispatch-overflow (tier decision 6)."
  }

  assert {
    condition     = alltrue([for c in output.callbacks : alltrue([for n in c.counts : can(regex("^[1-9][0-9]*$", n))])])
    error_message = "A CreateCallbackContact's delay or attempt count is not a static positive integer (VERIFY 16.2: delays and attempts must be static)."
  }

  # Nothing reachable from lines-busy creates a callback or invokes the
  # module: that branch is taken exactly when dispatch-overflow is full.
  assert {
    condition = alltrue(flatten([
      for name, reach in output.reach.from_lines_busy : [
        for id in reach : !contains(["CreateCallbackContact", "InvokeFlowModule"], output.types[name][id])
      ]
    ]))
    error_message = "A callback is offered from lines-busy, where dispatch-overflow is full and the create would take its error branch."
  }

  assert {
    condition     = length(output.callback_invokes) == 3 && alltrue([for i in output.callback_invokes : startswith(i.flow, "hh-district-") && i.id == "take-callback"])
    error_message = "The callback module is invoked by take-callback in each of the three district flows and nowhere else (both offers in a district flow share that one invoke)."
  }

  assert {
    condition = (
      output.offer_module.kind == "module" && output.offer_module.type == "MODULE" &&
      output.offer_module.start == "set-callback-number" &&
      output.offer_module.number_next == "create-callback" &&
      output.offer_module.create_next == "callback-taken" &&
      output.offer_module.create_errors == { NoMatchingError = "callback-refused" } &&
      alltrue([for id, next in output.offer_module.message_nexts : next == "done"]) &&
      output.offer_module.done_type == "EndFlowModuleExecution" &&
      strcontains(output.offer_module.texts["callback-refused"], "We cannot take a callback right now") &&
      strcontains(output.offer_module.texts["callback-taken"], "as soon as one comes free") &&
      !strcontains(join(" ", values(output.offer_module.texts)), "night shift")
    )
    error_message = "hh-offer-callback is the number, the create with its own copy for a refused create, shift-neutral copy (it runs at overflow-full mid-shift too), and every message ending the module."
  }

  assert {
    condition = alltrue([
      for name, o in output.district_offers :
      o.overflow_full_target == "overflow-full" && o.overflow_full_next == "offer-callback" &&
      o.after_hours_next == "offer-callback" &&
      o.offer_keys == { "1" = "take-callback", "2" = "sign-off" } &&
      tolist(o.offer_default) == tolist(["sign-off"]) &&
      tolist(o.offer_errors) == tolist(["InputTimeLimitExceeded", "NoMatchingCondition", "NoMatchingError"]) &&
      o.take_type == "InvokeFlowModule" && o.take_module == "$${cdref:module:hh-offer-callback@live}" && o.take_next == "hang-up" &&
      o.sign_off_type == "MessageParticipant" && o.sign_off_next == "hang-up" &&
      o.lines_busy_target == "lines-busy" && o.lines_busy_next == "hang-up"
    ]) && length(output.district_offers) == 3
    error_message = "A district flow does not offer the callback at overflow-full and after hours through module:hh-offer-callback@live, sign off every decline before the hang-up, and keep lines-busy a plain message."
  }

  assert {
    condition = alltrue([
      for name, q in output.queue_callbacks :
      q.share_eta_next == "check-eta-band" && q.band_value == "$.External.etaBand" &&
      tolist(q.band_later) == tolist(["offer-callback"]) && q.band_next == "check-sibling" &&
      q.offer_keys == { "1" = "set-callback-number", "2" = "check-sibling" } && tolist(q.offer_default) == tolist(["check-sibling"]) &&
      q.number_next == "create-callback" && tolist(q.number_targets) == tolist(["cannot-ring-back"]) && q.cannot_next == "hold" &&
      q.create_errors == { NoMatchingError = "callback-refused" } && q.refused_next == "hold" &&
      q.taken_next == "let-go" && q.let_go_type == "DisconnectParticipant"
    ]) && length(output.queue_callbacks) == 3
    error_message = "A queue flow does not offer the inline callback on a long wait, send its errors back to the hold, and end a taken callback with let-go."
  }

  # From the create's success branch the only terminal is a disconnect: a
  # flow that merely ended would leave the caller both queued and holding a
  # callback.
  assert {
    condition     = alltrue([for name, q in output.queue_callbacks : tolist(q.path_ends) == tolist(["DisconnectParticipant"])])
    error_message = "A queue flow's callback path reaches EndFlowExecution, or no terminal at all; it must end the call with DisconnectParticipant."
  }
}

# The hold A/B split (the TypeScript-first repository's VERIFY.md, DP1):
# every DistributeByPercentage covers 1 to 100 by its shape, ascending
# NumberLessThan thresholds at most 100 with a mirrored remainder, so its
# shares sum to 100; this one is 50/50, once per queue flow, on entry; each
# side records and tags holdVariant; hold is a Compare that plays the prompt
# for recorded and the spoken tips otherwise; the prompt reference is used
# in the recorded variant and nowhere else.
run "hold_ab" {
  command = plan

  module {
    source = "./fixtures/walks"
  }

  assert {
    condition = toset([for s in output.splits : "${s.flow}#${s.id}"]) == toset([
      "hh-queue-experience-graveyard-hill#pick-hold-variant",
      "hh-queue-experience-harborside#pick-hold-variant",
      "hh-queue-experience-old-town#pick-hold-variant",
    ])
    error_message = "The split runs once in each queue flow and nowhere else; the checks below would pass vacuously on none."
  }

  assert {
    condition = alltrue([
      for s in output.splits :
      alltrue([for o in s.operators : o == "NumberLessThan"]) &&
      alltrue([for i, t in s.thresholds : t > (i == 0 ? 1 : s.thresholds[i - 1]) && t <= 100 && floor(t) == t]) &&
      length(s.remainder) == 1 && s.next == s.remainder[0] &&
      sum(s.shares) == 100 && alltrue([for p in s.shares : p >= 1])
    ])
    error_message = "A DistributeByPercentage is not ascending NumberLessThan thresholds at most 100 with a remainder branch that next mirrors: its shares would not cover 1 to 100 once each."
  }

  assert {
    condition     = alltrue([for s in output.splits : tolist(s.shares) == tolist([50, 50]) && tolist(s.targets) == tolist(["note-spoken-variant"]) && tolist(s.remainder) == tolist(["note-recorded-variant"])])
    error_message = "The hold split is not 50/50: NumberLessThan 51 to the spoken side and the remainder to the recorded side."
  }

  assert {
    condition = alltrue([
      for name, h in output.hold_ab :
      h.check_moved_next == "pick-hold-variant" && h.split_next == "note-recorded-variant" &&
      alltrue([for v in ["spoken", "recorded"] : h.notes[v].type == "UpdateContactAttributes" && h.notes[v].attrs == { holdVariant = v } && h.notes[v].next == "tag-${v}-variant"]) &&
      alltrue([for v in ["spoken", "recorded"] : h.tags[v].type == "TagContact" && h.tags[v].tags == { holdVariant = v } && h.tags[v].next == "poll-crews"])
    ]) && length(output.hold_ab) == 3
    error_message = "A queue flow does not split on entry, or a side does not record holdVariant as an attribute and tag it before the poll."
  }

  assert {
    condition = alltrue([
      for name, h in output.hold_ab :
      h.hold_type == "Compare" && h.hold_value == "$.Attributes.holdVariant" &&
      h.hold_conditions == { recorded = "hold-recorded" } && h.hold_next == "hold-spoken" &&
      h.recorded_type == "MessageParticipantIteratively" && jsonencode(h.recorded_messages) == jsonencode([{ PromptId = "$${cdref:prompt:salt-line-tips}" }]) &&
      h.spoken_type == "MessageParticipantIteratively" && h.spoken_all_text &&
      h.recorded_interrupt == "30" && h.spoken_interrupt == "30" &&
      tolist(h.recorded_resume) == tolist(["poll-crews"]) && tolist(h.spoken_resume) == tolist(["poll-crews"]) &&
      tolist(h.recorded_errors) == tolist(["hold-spoken"]) && tolist(h.spoken_errors) == tolist(["settle-in"])
    ])
    error_message = "hold is not a Compare on holdVariant that plays prompt:salt-line-tips for recorded (falling back to the spoken tips) and the spoken tips otherwise, both interruptible every 30 s back to the poll."
  }

  assert {
    condition = output.prompt_refs == {
      "hh-queue-experience-graveyard-hill" = ["$${cdref:prompt:salt-line-tips}"]
      "hh-queue-experience-harborside"     = ["$${cdref:prompt:salt-line-tips}"]
      "hh-queue-experience-old-town"       = ["$${cdref:prompt:salt-line-tips}"]
    }
    error_message = "The prompt reference is used somewhere other than the recorded hold variant of each queue flow, or not there."
  }
}

# The fallback if Connect refuses a log group that already exists (VERIFY.md,
# T1): no group here, and the instance still plans.
run "flow_log_group_left_to_connect" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    manage_flow_log_group = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.connect_flow_logs) == 0 && aws_connect_instance.this.contact_flow_logs_enabled
    error_message = "With manage_flow_log_group false the module creates no flow log group, and flow logs stay enabled."
  }
}

# Values AWS would refuse at apply are refused at plan.
run "inputs_aws_would_refuse" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    log_retention_days = 10
    instance_alias     = "d-0123456789"
    name_prefix        = "tfacc-hh"
    queue_max_contacts = 0
    time_zone          = "America/New York"
  }

  expect_failures = [
    var.log_retention_days,
    var.instance_alias,
    var.name_prefix,
    var.queue_max_contacts,
    var.time_zone,
  ]
}

run "alias_longer_than_45_refused" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    instance_alias = "hollow-hour-tf-an-alias-that-is-far-too-long-to-use"
    name_prefix    = "HH"
  }

  expect_failures = [var.instance_alias, var.name_prefix]
}

run "valid_inputs_accepted" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    log_retention_days = 30
    instance_alias     = "hollow-hour-tf-adopted-1"
    name_prefix        = "hh-tf2"
    queue_max_contacts = 5
    time_zone          = "UTC"
  }

  assert {
    condition     = aws_connect_instance.this.instance_alias == "hollow-hour-tf-adopted-1" && aws_connect_queue.crew["old-town"].max_contacts == 5
    error_message = "Valid inputs are taken as given."
  }
}

run "dev_queue_cap" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    environment = "dev"
    hours       = "always_open"
  }

  assert {
    condition     = alltrue([for q in values(aws_connect_queue.crew) : q.max_contacts == 2]) && alltrue([for q in values(aws_connect_queue.shared) : q.max_contacts == 2])
    error_message = "Outside prod every queue holds two contacts, so an operator can fill one and hear the overflow."
  }
}

# A fourth district is one entry: its queue, its two flows, and a menu key.
run "four_districts" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    districts = [
      { slug = "old-town", name = "Old Town", overflow_to = "harborside" },
      { slug = "harborside", name = "Harborside", overflow_to = "graveyard-hill" },
      { slug = "graveyard-hill", name = "Graveyard Hill", overflow_to = "mill-pond" },
      { slug = "mill-pond", name = "Mill Pond", overflow_to = "old-town", hours = "always_open" },
    ]
  }

  assert {
    condition     = length(output.flowdocs) == 21 && length(aws_connect_queue.crew) == 4
    error_message = "A fourth district adds one crew queue, one district flow and one queue-experience flow."
  }

  assert {
    condition     = endswith(jsondecode(output.flowdocs["hh-district-menu"]).content.Actions[0].Parameters.Text, "For Mill Pond, press 4.")
    error_message = "The menu grows a fourth key."
  }

  assert {
    condition     = output.district_hours["mill-pond"] == "always_open" && output.district_hours["old-town"] == "night_shift"
    error_message = "A district's own hours override the environment's for that district only."
  }

  assert {
    condition     = contains(keys(output.flow_refs["hh-district-graveyard-hill"]), "queue:mill-pond-crew")
    error_message = "Graveyard Hill overflows to its overflow_to, Mill Pond."
  }
}

run "overflow_must_be_a_sibling" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    districts = [
      { slug = "old-town", name = "Old Town", overflow_to = "old-town" },
      { slug = "harborside", name = "Harborside", overflow_to = "nowhere" },
    ]
  }

  expect_failures = [var.districts]
}

run "season_is_standard_or_halloween" {
  command = plan

  module {
    source = "../modules/hollow-hour"
  }

  variables {
    season = "october"
  }

  expect_failures = [var.season]
}
