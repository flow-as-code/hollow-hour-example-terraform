# Tasks

The tiers, their acceptance criteria and the decisions they wait on are kept
once, in the TypeScript-first repository, and this repository mirrors each
change after it merges there. Each task file there has a "Terraform-first"
section with what changes here; this file lists those specifics in one
place so a change here can be checked against them.

| #   | Task          | Criteria                                                                                                                  | Status                                           |
| --- | ------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| T1  | First night   | [T1-first-night.md](https://github.com/flow-as-code/hollow-hour-example-typescript/blob/main/tasks/T1-first-night.md)     | live in dev, qa and prod, us-west-2 (2026-09-30) |
| T2  | Full moon     | [T2-full-moon.md](https://github.com/flow-as-code/hollow-hour-example-typescript/blob/main/tasks/T2-full-moon.md)         | live in dev, qa and prod, us-west-2 (2026-10-13); S1 to S5 passed on all three (VERIFY.md, T12) |
| T3  | Witching hour | [T3-witching-hour.md](https://github.com/flow-as-code/hollow-hour-example-typescript/blob/main/tasks/T3-witching-hour.md) | planned 2026-10-04; after the season             |
| T4  | Full coverage | [T4-full-coverage.md](https://github.com/flow-as-code/hollow-hour-example-typescript/blob/main/tasks/T4-full-coverage.md) | planned 2026-10-04; follows flow-as-code Phase D |

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
3. Live, once per tier, at the mirror of the tier's Close PR: dev, qa and
   prod in us-west-2, resource names `hh-tf-<env>-*`, a saved plan then
   apply, then a fresh plan that shows "No changes". Every other mirrored
   PR ends at `tofu test` and the equivalence check; the TypeScript-first
   plan's drift and scenario evidence is written for one apply per tier.

## T2: full moon

Where it stands (2026-10-05): the mirror of PRs 1 to 4 landed as one pull
request: the six single-resource flow files, the hold hooks in
`hh-district.tf`, `hh-district-menu.tf` and `hh-hotline-main.flow.tf`, the
plane check and the prank screen in the hotline, `hold`'s error falling to
`settle-in` in `hh-queue-experience.tf`, `hours:closed` in `hours.tf`, the
recording storage in `recordings.tf` (not `instance.tf`: a file of its own,
as that repository's `envs/bootstrap/recordings.tf`), the two Lambda
comment fixes, the tftest runs `dead_line`, `plane_check`, `holds`, `hooks`,
`prank_screen` and `callback_number` on walks over the planned FlowDocs
(`tests/fixtures/walks`, `tests/fixtures/reach`), and the snapshot at
`ce9d6f3` with `check.mjs` holding a map key no flow uses to a planned
resource. A read-only plan of dev showed 13 to add, 10 to change, 0 to
destroy (VERIFY.md, T9).

The mirror of PRs 5 to 7 landed as a second pull request the same day:
`open-work-order` in `hh-hotline-main.flow.tf`; `hh-offer-callback.flow.tf`
(the module alone, so flow-cli reads it) with its version and live alias in
`hh-offer-callback-release.tf`, the shape `hh-greeting.tf` carries, bound by
`hh-district.tf` as `module:hh-offer-callback@live` (that repository
invokes it through the alias, not unaliased as first planned: its
tasks/T2-full-moon.md, Deviations) at `after-hours` and the new
`overflow-full`, with `sign-off` before the hang-up and `lines-busy` left
plain; the inline callback in `hh-queue-experience.tf` ending in
DisconnectParticipant, and the hold A/B split there (`pick-hold-variant`,
`holdVariant` noted and tagged, `hold` a Compare over `hold-spoken` and
`hold-recorded`); `prompts.tf` with `prompts/salt-line-tips.wav` and `.txt`
copied byte for byte; `hashicorp/awscc ~> 1.104` in the module, the three
environments, `tests/` and the harness, configured in each environment with
`region` only, and the five lock files re-locked for four platforms
(`environments/dev` by `tofu providers lock`, the identical hashes copied
into the other four, each confirmed by `tofu init -lockfile=readonly`);
the plugin directory cached in every CI job; the tftest runs `callbacks`
and `hold_ab`, a `mock_provider "awscc"` in both test files, and the
prompt's bucket, object and tags in `prod`; the snapshot at `b8e5b3f` with
`check.mjs` naming the prompt and the in-set alias, and planning a copy of
the module in which the prompt is a `terraform_data` stand-in, because E1
was answered no: awscc validates its credentials against STS as it
configures (VERIFY.md, T10). A read-only plan of dev against the live Tier
1 state showed 22 to add, 10 to change, 0 to destroy (VERIFY.md, T11).

**Close (2026-10-13, UTC)**, from `main` at the merge of the mirror of
PRs 5 to 7, snapshot `b8e5b3f`; the evidence is VERIFY.md, T12.

- Checks, 15:48 to 15:51: fmt, validate of the five roots, `tofu test` (21
  passed, 0 failed), equivalence in dev, qa, prod and prod-october (19
  flows and modules, 312 actions).
- `bootstrap`, planned 15:49: no changes. The recording storage is in the
  module here, so it came with each environment's apply.
- Saved plans: dev 15:51, qa 15:52, prod 15:52, each 22 to add, 10 to
  change, 0 to destroy, and the three resource lists identical. Each
  environment read no CALL_RECORDINGS storage config, and 10 concurrent
  calls (L-12AB7C57), before its apply.
- Applies of those plans, one at a time, by hand: dev 16:50 to 16:51, qa
  16:51 to 16:52, prod 16:52 to 16:53, each "22 added, 10 changed, 0
  destroyed". Fresh plans: dev 16:54, qa 17:04, prod 17:04, each "No
  changes", which is the drift check here.
- Reads, dev 16:54 and qa and prod 17:04: RS1, HC1, P1 and DP1 accepted
  as authored on every instance, with no fallback taken.
- Scenarios S1 to S5 from the TypeScript-first repository, one run at a
  time, S4 first, each against a resource map built from that
  environment's state (38 references):

  | Environment | Started | S4      | S1     | S2      | S3     | S5     | Callbacks found after S4 |
  | ----------- | ------- | ------- | ------ | ------- | ------ | ------ | ------------------------ |
  | dev         | 16:55   | 121.5 s | 59.4 s | 100.6 s | 99.0 s | 46.7 s | 0, swept twice           |
  | qa          | 17:05   | 121.8 s | 60.2 s | 98.5 s  | 98.6 s | 46.4 s | 0, swept twice           |
  | prod        | 17:12   | 121.2 s | 59.3 s | 99.6 s  | 98.9 s | 46.5 s | 0, swept twice           |

  Every run passed, with no "Too Many Requests". No `StopContact` was needed (CB1).
  D1: dev's S4 contact holds the resolved advice as its Description, and
  a search by "Hollow Hour work order" found S2's, S3's and S4's contacts
  on each instance.
- Not exercised: the apply ran from an operator's credentials, not
  `deploy.yml`, so the deploy role (VERIFY.md, T4) and its `s3:GetObject`
  on the prompts bucket (P1) are still to be seen.

- **Module files**: new `hh-dead-line.flow.tf`, `hh-dead-whisper.flow.tf`,
  `hh-dead-hold.flow.tf`, `hh-dead-queue-experience.flow.tf`,
  `hh-customer-hold.flow.tf`, `hh-agent-hold.flow.tf`,
  `hh-offer-callback.flow.tf` with `hh-offer-callback-release.tf` (its
  version and live alias; the reader takes one resource per `.flow.tf`),
  and `hh-collect-address.flow.tf` once flow-as-code C04 is released. Edits
  to `hh-hotline-main.flow.tf` (plane check, prank screen, work order),
  `hh-district.tf` (the hold hooks, the callback offer, refs),
  `hh-queue-experience.tf` (the A/B split, the inline callback on
  `dispatch-overflow`, the `prompt:salt-line-tips` ref) and
  `hh-district-menu.tf` (the address Compare). New `prompts.tf`: a private
  bucket (suffixed with the instance alias's random id, as the recording
  bucket is; the module reads no caller identity, so the harness plans it
  offline), the committed audio as an object keyed on its MD5, and
  `awscc_connect_prompt`.
- **Providers**: `versions.tf` gains `hashicorp/awscc`;
  `environments/*/providers.tf` configure it with `region` only. awscc has
  no `default_tags`, `skip_credentials_validation` or
  `skip_requesting_account_id` (only `skip_metadata_api_check`), so
  `awscc_connect_prompt` carries the module's two tags itself as `tags`, a
  set of `{key, value}` objects, and a tftest run holds them equal to the
  aws `default_tags`. `tests/versions.tf` and
  `tools/equivalence/harness/main.tf` declare awscc as well, because
  `mock_provider` and the harness need it declared. The awscc package is
  hundreds of megabytes, and the fmt-validate matrix inits five roots per
  OpenTofu version, then `tofu test` and the harness init again, each
  under a 20-minute timeout, so the mirror of T2 PR 7 caches the plugin
  directory in CI (`actions/cache` keyed on the lock files, pinned to a
  commit SHA like every other action, with `TF_PLUGIN_CACHE_DIR` pointing
  every init at it).
- **tftest runs**: a `mock_provider "awscc"` with a `prompt_arn` default;
  new runs `dead_line`, `holds`, `prank_screen`, `callbacks` and `hold_ab`.
  `environments.tftest.hcl` still shows the roots differ only in their
  `terraform.tfvars`.
- **Equivalence**: a snapshot bump per mirrored PR; `REWRITES` in
  `check.mjs` learns `awscc_connect_prompt.X.prompt_arn` to `.name` and
  `expectedBindings` the same address, and the in-set module's alias,
  `flowascode_contact_flow_module_alias.hh_offer_callback_live.arn` to
  `<module name>@live`, the greeting alias's form: that repository invokes
  `module:hh-offer-callback@live` through a live alias after all (its
  Deviations: the typed `Refs.module` takes an alias), and its address maps
  carry no entry for an in-set key, so `check.mjs` expects
  `hh-offer-callback@live` for it as it does `hh-greeting-<season>@live`.
  Both plans run on a copy of the module with the prompt stood in for
  (E1, below).
- **Risk E1**, as rewritten 2026-10-05: with an awscc provider block
  carrying placeholder `access_key` and `secret_key`, `region` and
  `skip_metadata_api_check`, does `tofu plan` of a new
  `awscc_connect_prompt` make a Cloud Control call? The aws and flowascode
  `skip_` configuration cannot be reused, since awscc has none of it.
  Answered by the mirror of PR 7 on 2026-10-05 (VERIFY.md, T10,
  `harness-checked`): the provider does not get as far as Cloud Control; it
  calls STS `GetCallerIdentity` as it configures and fails on the
  placeholder keys (`InvalidClientTokenId`), so no plan with an awscc
  resource runs offline. The fallback is in place: `check.mjs` plans a
  copy of the module in which the prompt is a `terraform_data` stand-in
  with the same attributes, its references rewritten (`STAND_IN`), so
  awscc is never configured and the prompt's binding is still compared by
  the name `prompts.tf` declares. The harness root keeps awscc declared
  and configures it nowhere.
- **Recording storage**: that repository found no CALL_RECORDINGS storage
  config on any instance (2026-10-05), so `recordings.tf` adds one per
  environment: an `amazon-connect-` prefixed bucket (the only S3 grant the
  service-linked role carries) with SSE-S3, no customer KMS key, public
  access blocked, a 30-day expiry, and the storage config (tier decision 5;
  VERIFY.md, RS1). Landed with the mirror of PR 3.
- **Closed hours**: `hours:closed`, an `aws_connect_hours_of_operation`
  open for one minute a week (the provider requires one `config` block),
  in `hours.tf`, named `hh-tf-<env>-closed` so that repository's maps bind
  it, read by no flow, for S4's substitution (TypeScript-first VERIFY HC1).
  Landed with the mirror of PR 3.

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
- The provider floor in `modules/hollow-hour/versions.tf` (`~> 0.1.2`,
  whose comment keeps the constraint within 0.1 on purpose) is widened past
  `~> 0.1` in the same PR that first uses a Phase D typed block or ref key.
  Until then nothing here depends on FlowDoc 0.3: the roots plan HCL, not
  documents, and the provider computes the `flowdoc` field with its own
  version constant, so a document version never crosses to it. What an
  older provider refuses at validate is a typed sub-block or a ref-type key
  its catalog lacks. (Rewritten 2026-10-05; the earlier bullet named a gate
  that cannot trip.)
- `tools/equivalence/check.mjs` compares kind, type, start action,
  settings, refs and actions but not `flowdoc`, so a 0.3 snapshot beside a
  provider still writing 0.2 passes silently; the snapshot bump at T4 adds
  a `flowdoc` version comparison (or records why it stays excluded) so a
  reader-writer mismatch is visible.
- tftest runs and `check.mjs`'s refs rewrite learn each new reference type
  by flow-as-code D01's token name: `tasktemplate`, `casetemplate`,
  `casefield` (also as a `CaseRequestFields` map key, ADR 0008's default
  form), `assistant` and `phonenumber`.
- One supporting file per capability (`profiles.tf`, `cases.tf`,
  `tasks.tf`, `assist.tf`, `streaming.tf`) and one `*.flow.tf` per new flow.
