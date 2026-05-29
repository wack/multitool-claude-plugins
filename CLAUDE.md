# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Claude Code **plugin** (not a normal application). It ships one model-invoked
skill, `otel-setup`, that walks users through setting up OpenTelemetry (installing
from scratch when needed) and wiring it to MultiTool's OTLP endpoint. The skill
bundles a shell script (`scripts/multitool-onboard.sh`) that handles signup,
login, workspace selection, and API-key minting via the MultiTool management API
without exposing the user's password or the cleartext API key to the model. The
markdown artifacts are the load-bearing pieces; the script is the only
executable.

## Layout

- `.claude-plugin/plugin.json` — plugin manifest (name, version, description).
- `.claude-plugin/marketplace.json` — marketplace catalog so the repo can be
  added via `/plugin marketplace add wack/multitool-claude-plugins`. The plugin
  entry's `source` is `./`, meaning the plugin lives at the repo root.
- `skills/otel-setup/SKILL.md` — skill instructions + frontmatter. The
  `description` field is the trigger surface: Claude only auto-invokes the
  skill when the user's request matches phrasing here, so edits to that field
  directly affect invocation accuracy.
- `skills/otel-setup/references/<language>/index.md` — per-language snippets
  (TypeScript, Python, Go, Java, Ruby, Rust, PHP, .NET). SKILL.md instructs the
  model to read the matching reference *after* identifying the language, rather
  than loading all of them up front. Each reference has three sections (detect
  current state, install from scratch, configure for MultiTool) so it can
  serve every onboarding state in one file. Framework- and deploy-target-specific
  supplementary files live as siblings (e.g. `references/python/fastapi.md`,
  `references/typescript/vercel.md`) — none exist yet but the layout supports
  them.
- `skills/otel-setup/scripts/multitool-onboard.sh` — interactive script run by
  the user (not by the model) to obtain an API key. The script refuses to run
  without an interactive TTY, so the model cannot invoke it via the Bash tool
  and accidentally capture password input in its transcript. The model points
  the user at the script via the `!` prefix.

## Local development

```bash
claude --plugin-dir .
```

After editing any skill file, run `/reload-plugins` inside Claude Code to pick
up changes — no restart needed. The skill is model-invoked, so test it by
describing a MultiTool onboarding scenario, not by typing `/otel-setup`.

## Invariants the skill enforces

These are load-bearing details — when editing SKILL.md or any reference file,
do not let them drift:

- **OTLP endpoint:** `https://api.multitool.run/otlp/v1/traces`. HTTP only —
  the gRPC exporter will not work. Every reference file must use the
  `exporter-trace-otlp-http` package (or its per-language equivalent), never
  the gRPC variant.
- **Auth header:** `X-API-KEY: <value>` (uppercase, with the `X-` prefix),
  sourced from the `MULTI_API_KEY` env var. Never hardcoded. The earlier
  iteration of the skill used `api-key` — that name is wrong and should not
  appear anywhere in the repo.
- **Mandatory resource attributes** — all three must be set on the OTel
  **Resource** (not as span attributes) for MultiTool to ingest the traces
  correctly:
  - `service.name`, a stable identifier for the service.
  - `service.version`, non-empty and changing every deploy. MultiTool groups
    traces by it, so a static or empty value makes the product unusable.
  - `deployment.environment.name`, non-empty and differing across
    environments (typical values: `production`, `staging`, `development`).

  Only the *attribute names* are load-bearing; the *runtime source* of each
  value is the application's choice. The language references use
  `APP_VERSION` and `APP_ENVIRONMENT` as placeholder names in code samples
  because the code has to read from *something* — these are defaults the
  user can swap, not names MultiTool requires. SKILL.md instructs the
  agent to look for an existing convention (CI env exports, framework
  helpers like `NODE_ENV`/`RAILS_ENV`, Docker `ENV` declarations) before
  defaulting. Keep that framing intact when editing.
- **Mandatory span attribute on HTTP server spans:**
  `http.response.status_code` (per the OTel HTTP semantic conventions —
  https://opentelemetry.io/docs/specs/semconv/registry/attributes/http/).
  MultiTool relies on this to detect and analyze HTTP errors. Auto-instrumentation
  for every supported language sets this automatically; manual instrumentation
  must set it explicitly on each server span.
- **Plugin-owned env var name:** `MULTI_API_KEY`. This is the *only* env
  var name the plugin defines end-to-end — the onboarding script writes to
  it and the language references read from it. Treat it as a fixed name
  appearing in SKILL.md, every reference, the onboarding script, and the
  README; change it in all places at once or not at all. `APP_VERSION` and
  `APP_ENVIRONMENT` appear in the references but only as example defaults
  (see the resource-attributes invariant above) — those are not subject to
  this rule.

## Editing the skill description

The `description` frontmatter in `SKILL.md` is what Claude matches against to
decide whether to auto-invoke. It is intentionally permissive ("when in doubt,
use this skill") because missing an invocation is worse than an unnecessary
one. Preserve that bias when editing.
