# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The Tier 2 invariants that need a walk over a flow, for
# tests/flows.tftest.hcl: one module call (prod's values; the content is the
# same in every profile, tests/environments.tftest.hcl), the FlowDocs the
# provider computes decoded, and each question put to fixtures/reach. The
# run asserts on the outputs; what they mean is written beside each.

module "hollow_hour" {
  source      = "../../../modules/hollow-hour"
  environment = "prod"
}

locals {
  docs  = { for name, text in module.hollow_hour.flowdocs : name => jsondecode(text) }
  by_id = { for name, d in local.docs : name => { for a in d.content.Actions : a.Identifier => a } }
  main  = local.docs["hh-hotline-main"]
  dead  = local.docs["hh-dead-line"]
  offer = local.docs["hh-offer-callback"]

  # The generated flows, one of each per district.
  district_flows = { for name, d in local.docs : name => d if startswith(name, "hh-district-") && name != "hh-district-menu" }
  queue_flows    = { for name, d in local.docs : name => d if startswith(name, "hh-queue-experience-") }

  # The branch check-injured-first takes when the injured flow attribute is
  # yes, and the one it takes otherwise.
  injured_yes = [for c in local.by_id["hh-hotline-main"]["check-injured-first"].Transitions.Conditions : c.NextAction if c.Condition.Operands[0] == "yes"]
  injured_no  = [local.by_id["hh-hotline-main"]["check-injured-first"].Transitions.NextAction]
}

# The dead line is reachable, and never without the safety question.
module "dead_line" {
  source  = "../reach"
  actions = local.main.content.Actions
  start   = local.main.content.StartAction
}

module "dead_line_without_safety" {
  source  = "../reach"
  actions = local.main.content.Actions
  start   = local.main.content.StartAction
  cut     = ["ask-anyone-hurt"]
}

# A caller who said someone is hurt: from the emergency advice, with the
# injured attribute tracked as yes at check-injured-first, the screen is
# unreachable, and so is start-interview (the block that would reset it).
module "injured_caller" {
  source    = "../reach"
  actions   = local.main.content.Actions
  start     = "emergency-advice"
  overrides = { "check-injured-first" = local.injured_yes }
}

# Every path from the advice to the screen's Compare passes note-injury.
module "injured_without_note" {
  source  = "../reach"
  actions = local.main.content.Actions
  start   = "emergency-advice"
  cut     = ["note-injury"]
}

# An uninjured caller is screened: from start-interview, with the Compare
# taking its no-match branch, prank-score is reachable.
module "uninjured_caller" {
  source    = "../reach"
  actions   = local.main.content.Actions
  start     = "start-interview"
  overrides = { "check-injured-first" = local.injured_no }
}

# From the screen tag, stopping at the untag and the disconnect: nothing
# reachable may leave the flow with the tag set.
module "screen_tag" {
  source  = "../reach"
  actions = local.main.content.Actions
  start   = "tag-screen"
  cut     = ["untag-screen", "hang-up"]
}

# The held exception: what a failed untag-screen can reach.
module "after_failed_untag" {
  source    = "../reach"
  actions   = local.main.content.Actions
  start     = "untag-screen"
  overrides = { "untag-screen" = [for e in local.by_id["hh-hotline-main"]["untag-screen"].Transitions.Errors : e.NextAction] }
}

module "dead_all" {
  source  = "../reach"
  actions = local.dead.content.Actions
  start   = local.dead.content.StartAction
}

module "dead_without_welcome" {
  source  = "../reach"
  actions = local.dead.content.Actions
  start   = local.dead.content.StartAction
  cut     = ["dead-welcome"]
}

module "dead_without_patience" {
  source  = "../reach"
  actions = local.dead.content.Actions
  start   = local.dead.content.StartAction
  cut     = ["set-patience"]
}

# From lines-busy in each district flow, the branch taken exactly when
# dispatch-overflow is full: nothing reachable may create a callback or
# invoke the callback module (a callback into a full queue takes the error
# branch; tier decision 6).
module "from_lines_busy" {
  for_each = local.district_flows
  source   = "../reach"
  actions  = each.value.content.Actions
  start    = "lines-busy"
}

# The inline callback's success branch in each queue flow: what it reaches
# must end the call, never the flow alone.
module "callback_path" {
  for_each = local.queue_flows
  source   = "../reach"
  actions  = each.value.content.Actions
  start    = local.by_id[each.key]["create-callback"].Transitions.NextAction
}

output "reach" {
  description = "Each walk's reachable ids."
  value = {
    dead_line                = module.dead_line.reachable
    dead_line_without_safety = module.dead_line_without_safety.reachable
    injured_caller           = module.injured_caller.reachable
    injured_without_note     = module.injured_without_note.reachable
    uninjured_caller         = module.uninjured_caller.reachable
    screen_tag               = module.screen_tag.reachable
    after_failed_untag       = module.after_failed_untag.reachable
    dead_all                 = module.dead_all.reachable
    dead_without_welcome     = module.dead_without_welcome.reachable
    dead_without_patience    = module.dead_without_patience.reachable
    from_lines_busy          = { for name, m in module.from_lines_busy : name => m.reachable }
    callback_path            = { for name, m in module.callback_path : name => m.reachable }
  }
}

output "converged" {
  description = "Every walk's closure settled within its doublings."
  value = alltrue([
    module.dead_line.converged,
    module.dead_line_without_safety.converged,
    module.injured_caller.converged,
    module.injured_without_note.converged,
    module.uninjured_caller.converged,
    module.screen_tag.converged,
    module.after_failed_untag.converged,
    module.dead_all.converged,
    module.dead_without_welcome.converged,
    module.dead_without_patience.converged,
    alltrue([for name, m in module.from_lines_busy : m.converged]),
    alltrue([for name, m in module.callback_path : m.converged]),
  ])
}

output "types" {
  description = "Each flow's action ids and their types."
  value       = { for name, d in local.docs : name => { for a in d.content.Actions : a.Identifier => a.Type } }
}

# Every UpdateContactEventHooks block in the set: the hooks it sets and the
# flows they name.
output "hook_blocks" {
  value = flatten([
    for name, d in local.docs : [
      for a in d.content.Actions : {
        flow    = name
        id      = a.Identifier
        hooks   = keys(a.Parameters.EventHooks)
        targets = [for h, t in a.Parameters.EventHooks : trimsuffix(trimprefix(t, "$${cdref:flow:"), "}")]
      } if a.Type == "UpdateContactEventHooks"
    ]
  ])
}

# From every block that sets CustomerWhisper: the hook set by it and by the
# three blocks that follow it on next, so a chain is read as a list.
output "whisper_chains" {
  value = flatten([
    for name, d in local.docs : [
      for a in d.content.Actions : {
        flow  = name
        start = a.Identifier
        hooks = [
          for id in [
            a.Identifier,
            try(a.Transitions.NextAction, ""),
            try(local.by_id[name][a.Transitions.NextAction].Transitions.NextAction, ""),
            try(local.by_id[name][local.by_id[name][a.Transitions.NextAction].Transitions.NextAction].Transitions.NextAction, ""),
          ] :
          try(local.by_id[name][id].Type == "UpdateContactEventHooks" ? keys(local.by_id[name][id].Parameters.EventHooks)[0] : "(${local.by_id[name][id].Type})", "(missing)")
        ]
      } if a.Type == "UpdateContactEventHooks" && contains(keys(a.Parameters.EventHooks), "CustomerWhisper")
    ]
  ])
}

output "callback_setters" {
  description = "Every UpdateContactCallbackNumber: the number it sets and the errors it wires."
  value = flatten([
    for name, d in local.docs : [
      for a in d.content.Actions : {
        flow    = name
        id      = a.Identifier
        number  = try(a.Parameters.CallbackNumber, null)
        errors  = sort([for e in try(a.Transitions.Errors, []) : e.ErrorType])
        targets = distinct([for e in try(a.Transitions.Errors, []) : e.NextAction])
      } if a.Type == "UpdateContactCallbackNumber"
    ]
  ])
}

output "hold_flows" {
  description = "Each hold flow's shape: one MessageParticipantIteratively with no next, no branch and no interrupt is the rule."
  value = {
    for name, d in local.docs : name => {
      type      = d.connectType
      start     = d.content.StartAction
      actions   = length(d.content.Actions)
      first     = d.content.Actions[0].Identifier
      first_of  = d.content.Actions[0].Type
      has_next  = can(d.content.Actions[0].Transitions.NextAction)
      branches  = length(try(d.content.Actions[0].Transitions.Conditions, [])) + length(try(d.content.Actions[0].Transitions.Errors, []))
      interrupt = can(d.content.Actions[0].Parameters.InterruptFrequencySeconds)
      text      = join(" ", [for m in d.content.Actions[0].Parameters.Messages : m.Text])
    } if endswith(d.connectType, "_HOLD")
  }
}

output "dead" {
  description = "The dead line's settled shape, read block by block."
  value = {
    start           = local.dead.content.StartAction
    welcome_type    = local.by_id["hh-dead-line"]["dead-welcome"].Type
    welcome_text    = local.by_id["hh-dead-line"]["dead-welcome"].Parameters.Text
    welcome_next    = local.by_id["hh-dead-line"]["dead-welcome"].Transitions.NextAction
    recording_type  = local.by_id["hh-dead-line"]["record-agent-only"].Type
    recorded        = local.by_id["hh-dead-line"]["record-agent-only"].Parameters.RecordingBehavior.RecordedParticipants
    recording_errs  = length(try(local.by_id["hh-dead-line"]["record-agent-only"].Transitions.Errors, []))
    patience_type   = local.by_id["hh-dead-line"]["set-patience"].Type
    adjustment      = tostring(local.by_id["hh-dead-line"]["set-patience"].Parameters.QueueTimeAdjustmentSeconds)
    has_priority    = can(local.by_id["hh-dead-line"]["set-patience"].Parameters.QueuePriority)
    hours_id        = local.by_id["hh-dead-line"]["check-dead-hours"].Parameters.HoursOfOperationId
    hours_branches  = toset([for c in local.by_id["hh-dead-line"]["check-dead-hours"].Transitions.Conditions : c.NextAction])
    queue_id        = local.by_id["hh-dead-line"]["set-dead-queue"].Parameters.QueueId
    transfer_errors = sort([for e in local.by_id["hh-dead-line"]["transfer-to-dead"].Transitions.Errors : e.ErrorType])
    # The hooks set on a path from the start, one entry per block.
    hooks = [
      for a in local.dead.content.Actions : {
        id    = a.Identifier
        hooks = a.Parameters.EventHooks
      } if a.Type == "UpdateContactEventHooks" && contains(module.dead_all.reachable, a.Identifier)
    ]
  }
}

output "prank" {
  description = "The prank screen's blocks, read for the run's assertions."
  value = {
    after_last_question = distinct(concat(
      [for c in local.by_id["hh-hotline-main"]["ask-multiple"].Transitions.Conditions : c.NextAction if c.Condition.Operands[0] == "2"],
      [local.by_id["hh-hotline-main"]["note-multiple"].Transitions.NextAction],
    ))
    compares        = local.by_id["hh-hotline-main"]["check-injured-first"].Parameters.ComparisonValue
    injured_yes     = local.injured_yes
    injured_no      = local.injured_no
    injured_setters = { for a in local.main.content.Actions : a.Identifier => a.Parameters.FlowAttributes.injured.Value if a.Type == "UpdateFlowAttributes" && can(a.Parameters.FlowAttributes.injured) }
    score_lambda    = local.by_id["hh-hotline-main"]["prank-score"].Parameters.LambdaFunctionARN
    score_inputs    = sort(keys(local.by_id["hh-hotline-main"]["prank-score"].Parameters.LambdaInvocationAttributes))
    verdict_high    = [for c in local.by_id["hh-hotline-main"]["check-verdict"].Transitions.Conditions : c.NextAction if c.Condition.Operands[0] == "high"]
    tag             = local.by_id["hh-hotline-main"]["tag-screen"].Parameters.Tags
    kind_keys       = { for c in local.by_id["hh-hotline-main"]["kind-check"].Transitions.Conditions : c.Condition.Operands[0] => c.NextAction }
    kind_default    = distinct(concat([local.by_id["hh-hotline-main"]["kind-check"].Transitions.NextAction], [for e in local.by_id["hh-hotline-main"]["kind-check"].Transitions.Errors : e.NextAction]))
    untag_type      = local.by_id["hh-hotline-main"]["untag-screen"].Type
    untag_keys      = local.by_id["hh-hotline-main"]["untag-screen"].Parameters.TagKeys
    untag_next      = local.by_id["hh-hotline-main"]["untag-screen"].Transitions.NextAction
    untag_errors    = [for e in local.by_id["hh-hotline-main"]["untag-screen"].Transitions.Errors : e.NextAction]
    goodbye_text    = local.by_id["hh-hotline-main"]["dare-goodbye"].Parameters.Text
    goodbye_next    = local.by_id["hh-hotline-main"]["dare-goodbye"].Transitions.NextAction
  }
}

output "plane" {
  description = "The plane check's blocks."
  value = {
    after_safety_no = [for c in local.by_id["hh-hotline-main"]["ask-anyone-hurt"].Transitions.Conditions : c.NextAction if c.Condition.Operands[0] == "2"]
    lambda          = local.by_id["hh-hotline-main"]["plane-check"].Parameters.LambdaFunctionARN
    compares        = local.by_id["hh-hotline-main"]["check-plane"].Parameters.ComparisonValue
    beyond          = [for c in local.by_id["hh-hotline-main"]["check-plane"].Transitions.Conditions : c.NextAction if c.Condition.Operands[0] == "beyond"]
    otherwise       = local.by_id["hh-hotline-main"]["check-plane"].Transitions.NextAction
    to_flow         = local.by_id["hh-hotline-main"]["to-dead-line"].Parameters.ContactFlowId
  }
}

output "waits" {
  description = "Every Wait in the set, by flow and id: none is the rule."
  value       = flatten([for name, d in local.docs : [for a in d.content.Actions : "${name}#${a.Identifier}" if a.Type == "Wait"]])
}

output "refs" {
  description = "Each flow's reference tokens."
  value       = { for name, d in local.docs : name => [for r in d.refs : r.token] }
}

# Every CreateCallbackContact in the set: the queue it names (null when it
# names none, which would take the contact's current queue) and its three
# counts as written.
output "callbacks" {
  value = flatten([
    for name, d in local.docs : [
      for a in d.content.Actions : {
        flow   = name
        id     = a.Identifier
        queue  = try(a.Parameters.QueueId, null)
        counts = [for k in ["InitialCallDelaySeconds", "MaximumConnectionAttempts", "RetryDelaySeconds"] : tostring(try(a.Parameters[k], ""))]
      } if a.Type == "CreateCallbackContact"
    ]
  ])
}

# Every invoke of the callback module, by flow and id.
output "callback_invokes" {
  value = flatten([
    for name, d in local.docs : [
      for a in d.content.Actions : { flow = name, id = a.Identifier }
      if a.Type == "InvokeFlowModule" && a.Parameters.FlowModuleId == "$${cdref:module:hh-offer-callback@live}"
    ]
  ])
}

# The callback module's shape, block by block.
output "offer_module" {
  value = {
    kind          = local.offer.kind
    type          = local.offer.connectType
    start         = local.offer.content.StartAction
    actions       = length(local.offer.content.Actions)
    number_next   = local.by_id["hh-offer-callback"]["set-callback-number"].Transitions.NextAction
    create_next   = local.by_id["hh-offer-callback"]["create-callback"].Transitions.NextAction
    create_errors = { for e in local.by_id["hh-offer-callback"]["create-callback"].Transitions.Errors : e.ErrorType => e.NextAction }
    message_nexts = { for a in local.offer.content.Actions : a.Identifier => a.Transitions.NextAction if a.Type == "MessageParticipant" }
    texts         = { for a in local.offer.content.Actions : a.Identifier => a.Parameters.Text if a.Type == "MessageParticipant" }
    done_type     = local.by_id["hh-offer-callback"]["done"].Type
  }
}

# Each district flow's callback offer: where overflow-full and after-hours
# lead, what the offer's keys do, where a decline goes, and that lines-busy
# is left plain.
output "district_offers" {
  value = {
    for name, d in local.district_flows : name => {
      overflow_full_target = one([for e in local.by_id[name]["transfer-to-overflow"].Transitions.Errors : e.NextAction if e.ErrorType == "QueueAtCapacity"])
      overflow_full_next   = local.by_id[name]["overflow-full"].Transitions.NextAction
      after_hours_next     = local.by_id[name]["after-hours"].Transitions.NextAction
      offer_keys           = { for c in local.by_id[name]["offer-callback"].Transitions.Conditions : c.Condition.Operands[0] => c.NextAction }
      offer_default        = distinct(concat([local.by_id[name]["offer-callback"].Transitions.NextAction], [for e in local.by_id[name]["offer-callback"].Transitions.Errors : e.NextAction]))
      offer_errors         = sort([for e in local.by_id[name]["offer-callback"].Transitions.Errors : e.ErrorType])
      take_type            = local.by_id[name]["take-callback"].Type
      take_module          = local.by_id[name]["take-callback"].Parameters.FlowModuleId
      take_next            = local.by_id[name]["take-callback"].Transitions.NextAction
      sign_off_type        = local.by_id[name]["sign-off"].Type
      sign_off_next        = local.by_id[name]["sign-off"].Transitions.NextAction
      lines_busy_target    = one([for e in local.by_id[name]["transfer-to-dispatch"].Transitions.Errors : e.NextAction if e.ErrorType == "QueueAtCapacity"])
      lines_busy_next      = local.by_id[name]["lines-busy"].Transitions.NextAction
    }
  }
}

# Each queue flow's inline callback: offered on a long wait, errors back to
# the hold, and the terminal types its success branch reaches.
output "queue_callbacks" {
  value = {
    for name, d in local.queue_flows : name => {
      share_eta_next = local.by_id[name]["share-eta"].Transitions.NextAction
      band_value     = local.by_id[name]["check-eta-band"].Parameters.ComparisonValue
      band_later     = [for c in local.by_id[name]["check-eta-band"].Transitions.Conditions : c.NextAction if c.Condition.Operands[0] == "later"]
      band_next      = local.by_id[name]["check-eta-band"].Transitions.NextAction
      offer_keys     = { for c in local.by_id[name]["offer-callback"].Transitions.Conditions : c.Condition.Operands[0] => c.NextAction }
      offer_default  = distinct(concat([local.by_id[name]["offer-callback"].Transitions.NextAction], [for e in local.by_id[name]["offer-callback"].Transitions.Errors : e.NextAction]))
      number_next    = local.by_id[name]["set-callback-number"].Transitions.NextAction
      number_targets = distinct([for e in local.by_id[name]["set-callback-number"].Transitions.Errors : e.NextAction])
      cannot_next    = local.by_id[name]["cannot-ring-back"].Transitions.NextAction
      create_errors  = { for e in local.by_id[name]["create-callback"].Transitions.Errors : e.ErrorType => e.NextAction }
      refused_next   = local.by_id[name]["callback-refused"].Transitions.NextAction
      taken_next     = local.by_id[name]["callback-taken"].Transitions.NextAction
      let_go_type    = local.by_id[name]["let-go"].Type
      path_ends      = sort(distinct([for id in module.callback_path[name].reachable : local.by_id[name][id].Type if contains(["DisconnectParticipant", "EndFlowExecution"], local.by_id[name][id].Type)]))
    }
  }
}

# Every DistributeByPercentage in the set: its thresholds in order, the
# remainder branch, and the next that must mirror it.
output "splits" {
  value = flatten([
    for name, d in local.docs : [
      for a in d.content.Actions : {
        flow       = name
        id         = a.Identifier
        operators  = [for c in a.Transitions.Conditions : c.Condition.Operator]
        thresholds = [for c in a.Transitions.Conditions : tonumber(c.Condition.Operands[0])]
        targets    = [for c in a.Transitions.Conditions : c.NextAction]
        remainder  = [for e in try(a.Transitions.Errors, []) : e.NextAction if e.ErrorType == "NoMatchingCondition"]
        next       = try(a.Transitions.NextAction, "")
        # The shares, as the gaps between thresholds from 1, and the rest.
        shares = concat(
          [for i, t in a.Transitions.Conditions : tonumber(t.Condition.Operands[0]) - (i == 0 ? 1 : tonumber(a.Transitions.Conditions[i - 1].Condition.Operands[0]))],
          [101 - (length(a.Transitions.Conditions) == 0 ? 1 : tonumber(a.Transitions.Conditions[length(a.Transitions.Conditions) - 1].Condition.Operands[0]))],
        )
      } if a.Type == "DistributeByPercentage"
    ]
  ])
}

# Each queue flow's hold A/B blocks: the split on entry, each side's note and
# tag, and the hold's two variants.
output "hold_ab" {
  value = {
    for name, d in local.queue_flows : name => {
      check_moved_next = local.by_id[name]["check-moved"].Transitions.NextAction
      split_next       = local.by_id[name]["pick-hold-variant"].Transitions.NextAction
      notes = {
        for v in ["spoken", "recorded"] : v => {
          type  = local.by_id[name]["note-${v}-variant"].Type
          attrs = local.by_id[name]["note-${v}-variant"].Parameters.Attributes
          next  = local.by_id[name]["note-${v}-variant"].Transitions.NextAction
        }
      }
      tags = {
        for v in ["spoken", "recorded"] : v => {
          type = local.by_id[name]["tag-${v}-variant"].Type
          tags = local.by_id[name]["tag-${v}-variant"].Parameters.Tags
          next = local.by_id[name]["tag-${v}-variant"].Transitions.NextAction
        }
      }
      hold_type          = local.by_id[name]["hold"].Type
      hold_value         = local.by_id[name]["hold"].Parameters.ComparisonValue
      hold_conditions    = { for c in local.by_id[name]["hold"].Transitions.Conditions : c.Condition.Operands[0] => c.NextAction }
      hold_next          = local.by_id[name]["hold"].Transitions.NextAction
      recorded_type      = local.by_id[name]["hold-recorded"].Type
      recorded_messages  = local.by_id[name]["hold-recorded"].Parameters.Messages
      recorded_interrupt = tostring(local.by_id[name]["hold-recorded"].Parameters.InterruptFrequencySeconds)
      recorded_resume    = [for c in local.by_id[name]["hold-recorded"].Transitions.Conditions : c.NextAction]
      recorded_errors    = [for e in local.by_id[name]["hold-recorded"].Transitions.Errors : e.NextAction]
      spoken_type        = local.by_id[name]["hold-spoken"].Type
      spoken_all_text    = alltrue([for m in local.by_id[name]["hold-spoken"].Parameters.Messages : can(m.Text)])
      spoken_interrupt   = tostring(local.by_id[name]["hold-spoken"].Parameters.InterruptFrequencySeconds)
      spoken_resume      = [for c in local.by_id[name]["hold-spoken"].Transitions.Conditions : c.NextAction]
      spoken_errors      = [for e in local.by_id[name]["hold-spoken"].Transitions.Errors : e.NextAction]
    }
  }
}

# Every prompt reference in the set, by flow.
output "prompt_refs" {
  value = { for name, d in local.docs : name => [for r in d.refs : r.token if r.type == "prompt"] if length([for r in d.refs : r if r.type == "prompt"]) > 0 }
}
