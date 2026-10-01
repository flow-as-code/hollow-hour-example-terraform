# Snapshot source

The files in this directory are copied byte for byte from the
TypeScript-first repository,
[flow-as-code/hollow-hour-example-typescript](https://github.com/flow-as-code/hollow-hour-example-typescript),
at commit `db7f02a5d46f4e198b2cca2452d7511e5670691b` (2026-09-30), built
with flow-as-code 0.2.1. Its `flows/` and `seasonal/` FlowDocs have the same
actions as at `c3a50dd`; the move to 0.2.1 changed only `meta.generator` and
`meta.sourceHash`, in four of them.

- `flows/*.flowdoc.json` and `seasonal/*.flowdoc.json`, twelve files: the
  content `check.mjs` compares the module's flows against.
- `refs/dev.tfmap.json`, `refs/qa.tfmap.json`, `refs/prod.tfmap.json` and
  `refs/prod-october.tfmap.json`, as `<profile>.tfmap.json`: which Terraform
  address each reference key binds to in each profile there. `check.mjs`
  reads each address as the resource name it carries in that repository
  (`hh-<environment>-*`, from its `envs/*/supporting.tf`, `lambdas.tf` and
  `seasonal-*/greetings.tf`), with this repository's prefix
  (`hh-tf-<environment>-*`), and compares it with what the module binds.

They are never edited here.

To move the snapshot forward, copy the same files from a newer commit of that
repository, update the commit above, and run `node check.mjs`. A difference
it then reports is a change of behavior in one repository that the other
has not made yet. If that repository renames a resource or adds a kind of
binding, `expectedBindings` in `check.mjs` moves with it.
