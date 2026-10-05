# Snapshot source

The files in this directory are copied byte for byte from the
TypeScript-first repository,
[flow-as-code/hollow-hour-example-typescript](https://github.com/flow-as-code/hollow-hour-example-typescript),
at commit `b8e5b3f152f43cf032f56ae3cf1bd42796a6c96d` (2026-10-05, the merge
of its Tier 2 PR 7, so its `main` with Tier 2 PRs 1 to 7), built with
flow-as-code 0.2.1. The previous snapshot was `ce9d6f3` (2026-10-05, Tier 2
PRs 1 to 4); before that `db7f02a` (2026-09-30), Tier 1 as applied.

- `flows/*.flowdoc.json` and `seasonal/*.flowdoc.json`, nineteen files: the
  content `check.mjs` compares the module's flows against. Tier 2 PRs 2 to 4
  added `hh-customer-hold`, `hh-agent-hold`, `hh-dead-line`,
  `hh-dead-whisper`, `hh-dead-hold` and `hh-dead-queue-experience`, and
  changed `hh-hotline-main` (the plane check, the prank screen, the hold
  hooks, `note-ungraded`), the generated district flows and menu (the hold
  hooks) and the generated queue flows (`hold`'s error falls to `settle-in`).
  PRs 5 to 7 added `hh-offer-callback` (the one module in `flows/` there,
  kind `module`), and changed `hh-hotline-main` (`open-work-order`), the
  generated district flows (`overflow-full`, the callback offer through
  `module:hh-offer-callback@live`, `sign-off`) and the generated queue flows
  (the hold A/B split, the inline callback ending in DisconnectParticipant,
  `hold` as a Compare over `hold-spoken` and `hold-recorded`).
- `refs/dev.tfmap.json`, `refs/qa.tfmap.json`, `refs/prod.tfmap.json` and
  `refs/prod-october.tfmap.json`, as `<profile>.tfmap.json`: which Terraform
  address each reference key binds to in each profile there. `check.mjs`
  reads each address as the resource name it carries in that repository
  (`hh-<environment>-*`, from its `envs/*/supporting.tf`, `lambdas.tf` and
  `seasonal-*/greetings.tf`), with this repository's prefix
  (`hh-tf-<environment>-*`), and compares it with what the module binds. A
  key no flow binds (`hours:closed`, Tier 2 PR 3) must still name a resource
  the module plans. An in-set module key (`module:hh-offer-callback@live`)
  has no entry in any map: that repository's emitter binds it to the alias it
  writes beside the flows, and `check.mjs` expects `<module name>@<alias>`
  for it, as it does for the greetings.

They are never edited here.

To move the snapshot forward, copy the same files from a newer commit of that
repository, update the commit above, and run `node check.mjs`. A difference
it then reports is a change of behavior in one repository that the other
has not made yet. If that repository renames a resource or adds a kind of
binding, `expectedBindings` in `check.mjs` moves with it.
