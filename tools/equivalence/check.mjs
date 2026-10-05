#!/usr/bin/env node
/*
 * Copyright 2026 The flow-as-code Authors
 * SPDX-License-Identifier: Apache-2.0
 */
// CI check, not a deploy step: nothing here is needed to plan or apply an
// environment.
//
// Shows that modules/hollow-hour deploys the same flows as the
// TypeScript-first repository, bound to the same resources. Two checks, each
// run for every deploy profile (dev, qa and prod from their committed
// terraform.tfvars, and prod-october: prod with hours always_open and season
// halloween):
//
// 1. Content. It plans harness/ offline, reads the FlowDoc the flowascode
//    provider computes for every flow and module (the resource's flowdoc
//    attribute: the document with reference tokens in place, the same format
//    the TypeScript toolchain writes), and compares each, action by action,
//    with the FlowDoc of the same name in snapshot/, vendored from the
//    TypeScript-first repository at the commit snapshot/SOURCE.md records.
//    Compared: the set of names; per document its kind, Connect type, start
//    action, module settings, the reference tokens it makes, and every
//    action's Identifier, Type, Parameters and Transitions, in order. Not
//    compared: descriptions (each repository describes its own source) and
//    canvas layout.
//
// 2. Bindings. Content compares reference tokens (${cdref:queue:old-town-crew}),
//    so on its own it cannot see a flow whose refs bind that token to the
//    wrong queue, Lambda or greeting. ARNs are unknown until apply, so the
//    check plans a temporary copy of the module in which every refs value is
//    rewritten to a name the plan knows: a queue's or hours profile's name,
//    a Lambda's function_name, a flow's name, the prompt's name, and a
//    module alias as <module name>@<alias name>. Each flow's bindings must
//    then equal the TypeScript-first repository's for the same profile
//    (snapshot/<profile>.tfmap.json, which binds each key to a Terraform
//    address there), with that repository's names (hh-<environment>-*)
//    read as this one's (hh-tf-<environment>-*). A refs value the rewrite does
//    not cover stays unknown at plan, and fails the check rather than being
//    skipped. A key that repository's map binds and no flow uses (hours:closed,
//    which only a scenario substitutes) must still name a resource the module
//    plans, under the same name, so the two sets of resources stay the same.
//    An in-set module (hh-offer-callback, kind module in the snapshot) has no
//    map entry there: its emitter binds module:<name>@<alias> to the alias it
//    writes beside the flows, so the expected binding is <name>@<alias>, as
//    for the greetings.
//
// The flows that live one per file with no for_each or dynamic block
// (modules/hollow-hour/*.flow.tf) are read a second way too: by
// @flow-as-code/hcl, the TypeScript reader flow-cli and the studio use, which
// must return the same document as the snapshot. The district, menu,
// queue-experience and greeting resources iterate over var.districts or the
// seasons, which that reader refuses by design (COUNT_OR_FOR_EACH), so the
// provider's reading is the only one for them.
//
// Both sides are also checked by @flow-as-code/core: each must be a valid
// FlowDoc (assertFlowDoc) and the planned set must lint with no blocking
// finding.
//
// Both plans run against a temporary copy of the module, not the module
// itself: awscc validates its credentials against STS as it configures, with
// nothing to skip it (VERIFY.md, T10), so in the copy the one awscc resource,
// the prompt, is a terraform_data stand-in carrying the same attributes
// (STAND_IN below), and awscc is never configured. The prompt's binding is
// still compared, by the name the module's prompts.tf declares.
//
// Usage: node check.mjs [--write <dir>] [--no-init]
//   --write <dir>  also write prod's planned FlowDocs there, one
//                  <name>.flowdoc.json each, for flow-cli or the studio
//   --no-init      skip `tofu init` (the harness is already initialized)
// TOFU names the OpenTofu binary (default: tofu on PATH).

import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { assertFlowDoc, canonicalize, hasBlockingFindings, lint, serialize, toText } from "@flow-as-code/core";
import { toFlowDoc } from "@flow-as-code/hcl";

const HERE = fileURLToPath(new URL(".", import.meta.url));
const HARNESS = join(HERE, "harness");
const SNAPSHOT = join(HERE, "snapshot");
const REPO = join(HERE, "..", "..");
const MODULE = join(REPO, "modules", "hollow-hour");
const TOFU = process.env.TOFU || "tofu";

const args = process.argv.slice(2);
const writeDir = args.includes("--write") ? args[args.indexOf("--write") + 1] : undefined;
const init = !args.includes("--no-init");

// The harness's providers take placeholder keys; no AWS_* setting from the
// caller's shell (a profile, a role, an endpoint) may reach them.
const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith("AWS_")));
env.TF_IN_AUTOMATION = "1";
env.AWS_EC2_METADATA_DISABLED = "true";

function tofu(dir, argv, extraEnv = {}) {
  const r = spawnSync(TOFU, ["-chdir=" + dir, ...argv], {
    env: { ...env, ...extraEnv },
    encoding: "utf8",
    maxBuffer: 256 * 1024 * 1024,
  });
  if (r.error) throw new Error(`${TOFU} ${argv[0]}: ${r.error.message}`);
  if (r.status !== 0) {
    process.stderr.write(r.stdout + r.stderr);
    throw new Error(`${TOFU} ${argv[0]} exited ${r.status}`);
  }
  return r.stdout;
}

// The deploy profiles, read from the roots' committed terraform.tfvars so the
// check follows the files; prod-october is prod with the two October lines
// (README.md, "The season").
function profiles() {
  const tfvars = (env) =>
    Object.fromEntries(
      [...readFileSync(join(REPO, "environments", env, "terraform.tfvars"), "utf8").matchAll(/^([a-z_]+)\s*=\s*"([^"]*)"/gm)].map((m) => [
        m[1],
        m[2],
      ]),
    );
  const pick = ({ environment, hours, season }) => ({ environment, hours, season });
  return {
    dev: pick(tfvars("dev")),
    qa: pick(tfvars("qa")),
    prod: pick(tfvars("prod")),
    "prod-october": { ...pick(tfvars("prod")), hours: "always_open", season: "halloween" },
  };
}

// Plans a harness directory for one profile and returns `tofu show -json`.
function plan(dir, profile, extraEnv) {
  const work = mkdtempSync(join(tmpdir(), "hh-equivalence-"));
  try {
    const out = join(work, "equivalence.tfplan");
    const vars = Object.entries(profile).flatMap(([k, v]) => ["-var", `${k}=${v}`]);
    tofu(dir, ["plan", "-input=false", "-no-color", "-lock=false", "-refresh=false", ...vars, "-out=" + out], extraEnv);
    return JSON.parse(tofu(dir, ["show", "-json", "-no-color", out], extraEnv));
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

function plannedFlowDocs(shown) {
  const value = shown?.planned_values?.outputs?.flowdocs?.value;
  if (!value || typeof value !== "object") {
    throw new Error("The plan has no known flowdocs output; the provider did not compute the FlowDocs at plan time.");
  }
  return Object.fromEntries(Object.entries(value).map(([name, text]) => [name, JSON.parse(text)]));
}

// Each flow's and module's refs, by name, from the planned resources. A value
// the plan does not know yet is recorded as null.
function plannedRefs(shown) {
  const out = {};
  const visit = (mod) => {
    for (const r of mod?.resources ?? []) {
      if (r.type !== "flowascode_contact_flow" && r.type !== "flowascode_contact_flow_module") continue;
      const change = shown.resource_changes.find((c) => c.address === r.address);
      const unknown = change?.change?.after_unknown?.refs;
      const refs = {};
      const keys = new Set([...Object.keys(r.values.refs ?? {}), ...Object.keys(unknown && typeof unknown === "object" ? unknown : {})]);
      for (const k of keys) {
        const v = r.values.refs?.[k];
        refs[k] = typeof v === "string" && !(unknown && unknown[k] === true) ? v : null;
      }
      if (unknown === true) refs["(the whole refs map)"] = null;
      out[r.values.name] = refs;
    }
    for (const child of mod?.child_modules ?? []) visit(child);
  };
  visit(shown?.planned_values?.root_module);
  return out;
}

// The rewrite that makes every binding known at plan: the attribute each
// refs value reads, swapped for one that names the same resource. Written
// against the module's own resource addresses; a binding it misses stays
// unknown and is reported.
const REWRITES = [
  [/\b(aws_connect_queue\.(?:crew|shared)\[[^\]]+\])\.arn\b/g, "$1.name"],
  [/\b(aws_connect_hours_of_operation\.profile\[.+?\])\.arn\b/g, "$1.name"],
  [/\baws_connect_lambda_function_association\.stub\[([^\]]+)\]\.function_arn\b/g, "aws_lambda_function.stub[$1].function_name"],
  [
    /\bflowascode_contact_flow_module_alias\.hh_greeting_live\[(.+?)\]\.arn\b/g,
    '"$${flowascode_contact_flow_module.hh_greeting[$1].name}@$${flowascode_contact_flow_module_alias.hh_greeting_live[$1].name}"',
  ],
  [
    /\bflowascode_contact_flow_module_alias\.hh_offer_callback_live\.arn\b/g,
    '"$${flowascode_contact_flow_module.hh_offer_callback.name}@$${flowascode_contact_flow_module_alias.hh_offer_callback_live.name}"',
  ],
  [/\b(flowascode_contact_flow\.[a-z_]+(?:\[[^\]]+\])?)\.arn\b/g, "$1.name"],
  [/\b(awscc_connect_prompt\.[a-z_]+)\.prompt_arn\b/g, "$1.name"],
];

// The stand-in for the awscc provider's one resource (E1; VERIFY.md, T10):
// the prompt becomes a terraform_data whose input is the same attributes,
// so its name is the one prompts.tf declares; prompt_arn, unknown at plan
// like the ARN, becomes the stand-in's id, and name its input's (output
// would be unknown at plan, since the input also carries the instance ARN).
// The prompt's binding stays in the check: REWRITES turns .prompt_arn into
// .name first, and this turns that into the stand-in's name.
const STAND_IN = [
  [/resource "awscc_connect_prompt" "([a-z_]+)" \{\n([\s\S]*?)\n\}\n/g, 'resource "terraform_data" "$1" {\n  input = {\n$2\n  }\n}\n'],
  [/\bawscc_connect_prompt\.([a-z_]+)\.prompt_arn\b/g, "terraform_data.$1.id"],
  [/\bawscc_connect_prompt\.([a-z_]+)\.name\b/g, "terraform_data.$1.input.name"],
];

// A copy of the module and the harness, laid out as in the repository, with
// the prompt stood in for and, when named, the refs values rewritten. It
// shares the harness's initialized providers through TF_DATA_DIR, so it
// needs no second init.
function moduleCopy({ named }) {
  const root = mkdtempSync(join(tmpdir(), named ? "hh-bindings-" : "hh-content-"));
  const mod = join(root, "modules", "hollow-hour");
  const harness = join(root, "tools", "equivalence", "harness");
  cpSync(MODULE, mod, { recursive: true, filter: (src) => !/[\\/]\.(build|terraform)([\\/]|$)/.test(src) });
  mkdirSync(harness, { recursive: true });
  for (const f of ["main.tf", ".terraform.lock.hcl"]) cpSync(join(HARNESS, f), join(harness, f));
  let stoodIn = 0;
  for (const f of readdirSync(mod).filter((f) => f.endsWith(".tf"))) {
    let text = readFileSync(join(mod, f), "utf8");
    if (named) for (const [re, to] of REWRITES) text = text.replace(re, to);
    for (const [re, to] of STAND_IN) {
      stoodIn += (text.match(re) ?? []).length;
      text = text.replace(re, to);
    }
    writeFileSync(join(mod, f), text);
  }
  if (stoodIn === 0) throw new Error("STAND_IN matched nothing: the module no longer holds awscc_connect_prompt as check.mjs expects.");
  return { root, harness, env: { TF_DATA_DIR: join(HARNESS, ".terraform") } };
}

// The names the module plans for the resources a reference key can bind:
// queues, hours profiles, prompts and Lambdas. A key no flow binds is
// checked against these.
function plannedNames(shown) {
  const out = new Set();
  const visit = (mod) => {
    for (const r of mod?.resources ?? []) {
      if (r.type === "aws_connect_queue" || r.type === "aws_connect_hours_of_operation") out.add(r.values.name);
      if (r.type === "aws_lambda_function") out.add(r.values.function_name);
      // The prompt, as its stand-in (STAND_IN) carries it.
      if (r.type === "terraform_data" && typeof r.values.input?.name === "string") out.add(r.values.input.name);
    }
    for (const child of mod?.child_modules ?? []) visit(child);
  };
  visit(shown?.planned_values?.root_module);
  return out;
}

// What each reference key binds in the TypeScript-first repository, by name.
// Its tfmaps bind keys to Terraform addresses in its envs/<environment>/;
// these are the names those addresses carry there (its envs/*/supporting.tf,
// lambdas.tf and seasonal-*/greetings.tf), read with this repository's
// prefix. flow: keys, and module:<name>@<alias> keys for a module in the
// set, are bound by the emitter itself and have no map entry.
function expectedBindings(profileName, environment) {
  const map = JSON.parse(readFileSync(join(SNAPSHOT, `${profileName}.tfmap.json`), "utf8"));
  const ts = `hh-${environment}`;
  const tf = (name) => name.replace(new RegExp(`^${ts}-`), `hh-tf-${environment}-`);
  const rules = [
    [/^aws_connect_queue\.crew\["([^"]+)"\]\.arn$/, (m) => tf(`${ts}-${m[1]}-crew`)],
    [/^aws_connect_queue\.shared\["([^"]+)"\]\.arn$/, (m) => tf(`${ts}-${m[1]}`)],
    [/^aws_connect_hours_of_operation\.([a-z_]+)\.arn$/, (m) => tf(`${ts}-${m[1].replaceAll("_", "-")}`)],
    [/^aws_connect_lambda_function_association\.connect\["([^"]+)"\]\.function_arn$/, (m) => tf(`${ts}-${m[1]}`)],
    [/^data\.terraform_remote_state\.seasonal\.outputs\.greeting_([a-z]+)_live_arn$/, (m) => `hh-greeting-${m[1]}@live`],
    [/^awscc_connect_prompt\.([a-z_]+)\.prompt_arn$/, (m) => tf(`${ts}-${m[1].replaceAll("_", "-")}`)],
  ];
  const out = {};
  for (const [key, address] of Object.entries(map)) {
    const rule = rules.find(([re]) => re.test(address));
    out[key] = rule ? rule[1](address.match(rule[0])) : { unmapped: address };
  }
  return out;
}

// The binding the emitter makes itself for a key no map holds: a flow in
// the set by its name, a module in the set by its alias ARN.
function inSetBinding(key, inSetModules) {
  if (key.startsWith("flow:")) return key.slice("flow:".length);
  const m = /^module:([^@]+)@(.+)$/.exec(key);
  if (m && inSetModules.has(m[1])) return `${m[1]}@${m[2]}`;
  return undefined;
}

function compareBindings(profileName, environment, refsByFlow, planned, inSetModules) {
  const want = expectedBindings(profileName, environment);
  const out = [];
  let count = 0;
  const used = new Set(Object.values(refsByFlow).flatMap((refs) => Object.keys(refs)));
  for (const [key, expected] of Object.entries(want).sort()) {
    if (used.has(key) || typeof expected === "object") continue;
    count++;
    if (!planned.has(expected)) {
      out.push(`${profileName}: ${key} is bound there to ${expected} and used by no flow; the module plans no resource of that name`);
    }
  }
  for (const [flow, refs] of Object.entries(refsByFlow).sort()) {
    for (const [key, got] of Object.entries(refs).sort()) {
      count++;
      const expected = want[key] ?? inSetBinding(key, inSetModules);
      if (got === null) {
        out.push(`${profileName}: ${flow} binds ${key} to a value the plan does not know; extend REWRITES in check.mjs to name it`);
      } else if (expected === undefined) {
        out.push(`${profileName}: ${flow} binds ${key}, which the TypeScript-first repository's ${profileName}.tfmap.json does not bind`);
      } else if (typeof expected === "object") {
        out.push(`${profileName}: ${key} is bound there to ${expected.unmapped}, which check.mjs cannot name`);
      } else if (got !== expected) {
        out.push(`${profileName}: ${flow} binds ${key} to ${got}; the TypeScript-first repository binds it to ${expected}`);
      }
    }
  }
  return { problems: out, count };
}

function snapshotFlowDocs() {
  const docs = {};
  for (const f of readdirSync(SNAPSHOT).filter((f) => f.endsWith(".flowdoc.json")).sort()) {
    const doc = JSON.parse(readFileSync(join(SNAPSHOT, f), "utf8"));
    docs[doc.name] = doc;
  }
  return docs;
}

// Object keys in byte order at every depth, so key order never counts as a
// difference; array order does.
function sortKeys(value) {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((k) => [k, sortKeys(value[k])]),
    );
  }
  return value;
}

const refKeys = (doc) => (doc.refs ?? []).map((r) => r.token).sort();

// Every difference between two documents of the same name, as lines.
function compare(name, want, got) {
  const out = [];
  const same = (what, a, b) => {
    if (!isDeepStrictEqual(sortKeys(a), sortKeys(b))) {
      out.push(`${name}: ${what} differs\n    snapshot: ${JSON.stringify(a)}\n    module:   ${JSON.stringify(b)}`);
    }
  };
  same("kind", want.kind, got.kind);
  same("connectType", want.connectType, got.connectType);
  same("StartAction", want.content.StartAction, got.content.StartAction);
  same("Settings", want.content.Settings ?? null, got.content.Settings ?? null);
  same("references", refKeys(want), refKeys(got));
  // canonicalize is the toolchain's own normal form: each action as
  // Identifier, Type, sorted Parameters and Transitions.
  const wantActions = canonicalize(want).content.Actions;
  const gotActions = canonicalize(got).content.Actions;
  const ids = (actions) => actions.map((a) => a.Identifier);
  same("action order", ids(wantActions), ids(gotActions));
  const byId = new Map(gotActions.map((a) => [a.Identifier, a]));
  for (const a of wantActions) {
    const b = byId.get(a.Identifier);
    if (!b) continue; // reported by the order check
    same(`action ${a.Identifier}`, a, b);
  }
  return out;
}

function main() {
  const want = snapshotFlowDocs();
  for (const [name, doc] of Object.entries(want)) assertFlowDoc(doc, `snapshot ${name}`);
  const wantNames = Object.keys(want).sort();
  const inSetModules = new Set(Object.values(want).filter((d) => d.kind === "module" && !d.name.startsWith("hh-greeting-")).map((d) => d.name));
  const problems = [];

  if (init) tofu(HARNESS, ["init", "-input=false", "-no-color", "-lockfile=readonly"]);
  const content = moduleCopy({ named: false });
  const named = moduleCopy({ named: true });
  let prodDocs;
  let actions = 0;
  let bindings = 0;
  const all = profiles();
  try {
    for (const [profileName, profile] of Object.entries(all)) {
      // 1. Content.
      const got = plannedFlowDocs(plan(content.harness, profile, content.env));
      if (profileName === "prod") prodDocs = got;
      for (const [name, doc] of Object.entries(got)) assertFlowDoc(doc, `planned ${name} (${profileName})`);
      const gotNames = Object.keys(got).sort();
      for (const n of wantNames.filter((n) => !got[n])) problems.push(`${profileName}: ${n}: in the snapshot, not deployed by the module`);
      for (const n of gotNames.filter((n) => !want[n])) problems.push(`${profileName}: ${n}: deployed by the module, not in the snapshot`);
      for (const name of wantNames.filter((n) => got[n])) {
        if (profileName === "prod") actions += want[name].content.Actions.length;
        problems.push(...compare(`${profileName}: ${name}`, want[name], got[name]));
      }
      const findings = lint(Object.values(got));
      if (hasBlockingFindings(findings)) problems.push(`${profileName}: lint:\n${toText(findings)}`);

      // 2. Bindings.
      const namedPlan = plan(named.harness, profile, named.env);
      const result = compareBindings(profileName, profile.environment, plannedRefs(namedPlan), plannedNames(namedPlan), inSetModules);
      problems.push(...result.problems);
      bindings += result.count;
    }
  } finally {
    rmSync(content.root, { recursive: true, force: true });
    rmSync(named.root, { recursive: true, force: true });
  }

  // The TypeScript reader, on every file it can read.
  const flowFiles = readdirSync(MODULE).filter((f) => f.endsWith(".flow.tf")).sort();
  for (const f of flowFiles) {
    const { doc } = toFlowDoc(readFileSync(join(MODULE, f), "utf8"), { fileName: f });
    assertFlowDoc(doc, `${f} read by @flow-as-code/hcl`);
    if (!want[doc.name]) problems.push(`${f}: ${doc.name} is not in the snapshot`);
    else problems.push(...compare(`${doc.name} (${f}, read by @flow-as-code/hcl)`, want[doc.name], doc));
  }

  if (writeDir && prodDocs) {
    mkdirSync(writeDir, { recursive: true });
    for (const [name, doc] of Object.entries(prodDocs)) writeFileSync(join(writeDir, `${name}.flowdoc.json`), serialize(doc));
    console.log(`Wrote ${Object.keys(prodDocs).length} FlowDocs (prod) to ${writeDir}.`);
  }

  if (problems.length > 0) {
    console.error(problems.join("\n"));
    console.error(`\nNot equivalent: ${problems.length} difference(s).`);
    process.exit(1);
  }
  const source = readFileSync(join(SNAPSHOT, "SOURCE.md"), "utf8").match(/commit `([0-9a-f]{40})`/)?.[1] ?? "unknown commit";
  console.log(
    `Equivalent in ${Object.keys(all).length} profiles (${Object.keys(all).join(", ")}): ` +
      `${wantNames.length} flows and modules, ${actions} actions, identical to the snapshot as the provider plans them; ` +
      `${bindings} bindings (a flow's, or a key only a scenario uses), each to the resource the TypeScript-first repository binds; ` +
      `and ${flowFiles.length} flows as @flow-as-code/hcl reads their .flow.tf (${source}).`,
  );
  const findings = lint(Object.values(prodDocs ?? {}));
  if (findings.length > 0) console.log(`Lint (non-blocking):\n${toText(findings)}`);
}

main();
