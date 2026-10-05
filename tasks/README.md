# Tasks

The tiers, their acceptance criteria and the decisions they wait on are kept
once, in the TypeScript-first repository, and this repository mirrors each
change after it merges there. Each task file there has a "Terraform-first"
section with what changes here; this file lists those specifics in one
place so a change here can be checked against them.

| #   | Task          | Criteria                                                                                                                      | Status                                               |
| --- | ------------- | ----------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| T1  | First night   | [T1-first-night.md](https://github.com/flow-as-code/hollow-hour-example-typescript/blob/main/tasks/T1-first-night.md)         | live in dev, qa and prod, us-west-2 (2026-09-30)     |
| T2  | Full moon     | [T2-full-moon.md](https://github.com/flow-as-code/hollow-hour-example-typescript/blob/main/tasks/T2-full-moon.md)             | planned 2026-10-04; not started                      |
| T3  | Witching hour | [T3-witching-hour.md](https://github.com/flow-as-code/hollow-hour-example-typescript/blob/main/tasks/T3-witching-hour.md)     | planned 2026-10-04; after the season                 |
| T4  | Full coverage | [T4-full-coverage.md](https://github.com/flow-as-code/hollow-hour-example-typescript/blob/main/tasks/T4-full-coverage.md)     | planned 2026-10-04; follows flow-as-code Phase D     |

The tier decisions (phone number, Lex, agent users, prompt audio, recording
storage, the callback queue) are in that repository's
[tasks/README.md](https://github.com/flow-as-code/hollow-hour-example-typescript/blob/main/tasks/README.md)
and bind here too. Evidence that only this repository can produce (a plan,
an apply, a harness run) is recorded in this repository's `VERIFY.md` and in
the task file's "Where the criteria stand" with its UTC time.

## How a change lands here

1. The TypeScript-first PR merges.
2. The mirror PR here changes the module, its tests and the snapshot
   together:
   - the flows as single-resource `*.flow.tf` files in
     `modules/hollow-hour/`, readable by `@flow-as-code/hcl`;
   - a `tests/flows.tftest.hcl` run per invariant the TypeScript-first
     tests hold, so a broken invariant fails here as well;
   - `tools/equivalence/snapshot/` re-vendored at the merge commit, recorded
     in `snapshot/SOURCE.md`, and `check.mjs` green for every profile.
3. Live: dev, qa and prod in us-west-2, resource names `hh-tf-<env>-*`, a
   saved plan then apply, then a fresh plan that shows "No changes".

## T2: full moon

- **Module files**: new `hh-dead-line.flow.tf`, `hh-dead-whisper.flow.tf`,
  `hh-dead-hold.flow.tf`, `hh-dead-queue-experience.flow.tf`,
  `hh-customer-hold.flow.tf`, `hh-agent-hold.flow.tf`,
  `hh-offer-callback.flow.tf`, and `hh-collect-address.flow.tf` once
  flow-as-code C04 is released. Edits to `hh-hotline-main.flow.tf` (plane
  check, prank screen, work order), `hh-district.tf` (the hold hooks, the
  callback offer, refs), `hh-queue-experience.tf` (the A/B split, the inline
  callback on `dispatch-overflow`, the `prompt:salt-line-tips` ref) and
  `hh-district-menu.tf` (the address Compare). New `prompts.tf`: a private
  bucket, the committed audio as an object, and `awscc_connect_prompt`.
- **Providers**: `versions.tf` gains `hashicorp/awscc`;
  `environments/*/providers.tf` configure it with the same Region and
  default tags as aws.
- **tftest runs**: a `mock_provider "awscc"` with a `prompt_arn` default;
  new runs `dead_line`, `holds`, `prank_screen`, `callbacks` and `hold_ab`.
  `environments.tftest.hcl` still shows the roots differ only in their
  `terraform.tfvars`.
- **Equivalence**: a snapshot bump per mirrored PR; `expectedBindings` and
  the refs rewrite in `check.mjs` learn the `awscc_connect_prompt` name.
- **Risk E1**: the harness plans offline with placeholder credentials and
  every `skip_` flag. awscc works through Cloud Control and may not plan
  that way. The mirror of T2 PR 7 (the first awscc resource) answers E1
  before it merges and records it in `VERIFY.md`; the fallback is an
  override in `harness/` that stands in for the awscc resources without
  skipping the prompt's binding check.
- **Recording storage**: if an instance has no CALL_RECORDINGS storage
  config, it is added in `instance.tf`.

## T3: witching hour

- **Module files**: `hh-transfer-to-bo.flow.tf`,
  `hh-escalate-lantern.flow.tf`, `hh-callback-whisper.flow.tf`,
  `hh-field-guide-chat.flow.tf`; new `users.tf` (routing profile, the user
  `hh-tf-<env>-bo`, `random_password` with `ignore_changes`),
  `quick_connects.tf`, `views.tf`, and `lex.tf` if Lex is gated in, behind
  no flag, because every environment gets the same flows.
- **Queues**: `queues.tf` gains `quick_connect_ids` (never the Lantern Crew
  quick connect on the Lantern Crew queue, which would be a cycle) and
  `outbound_caller_config { outbound_flow_id }`.
- **tftest runs**: transfers, quick-connect placement, the chat flow, the
  outbound whisper; mock defaults for the user, view and Lex alias ARNs.
- **Equivalence**: the refs rewrite learns the `aws_connect_user`, view and
  Lex alias names.
- **S12 here**: `flow-cli export --author tf` for the console-built flow,
  an `import {}` block, and a plan with no changes.

## T4: full coverage

- Most new resources are awscc-only (task templates, Cases, the AI agents
  assistant, predefined attributes, user proficiencies, integration
  associations), so E1 must be settled first.
- The provider floor in `versions.tf` rises with each provider release that
  vendors the conformance the npm release uses; FlowDoc 0.3 (flow-as-code
  D01) needs the provider that reads it before any root plans a 0.3
  document.
- One supporting file per capability (`profiles.tf`, `cases.tf`,
  `tasks.tf`, `assist.tf`, `streaming.tf`) and one `*.flow.tf` per new flow.
