---
name: otel-setup
description: >
  Sets up OpenTelemetry tracing for an application and connects it to MultiTool.
  Handles the full onboarding flow: detects the application's language, checks
  whether OpenTelemetry is already installed (and whether it's already pointed
  at MultiTool), helps the user create a MultiTool account and API key if they
  don't have one, then makes the code changes needed to send traces to
  MultiTool. Use this skill whenever a user mentions MultiTool in the context
  of tracing, monitoring, observability, or onboarding — including phrasings
  like "I want to try MultiTool", "how do I use MultiTool with my service?",
  "how do I get started with MultiTool?", "how can I get MultiTool to recognize
  my service?", "I want to start monitoring with MultiTool", "set up MultiTool
  in this repo", or "connect this app to MultiTool". Also trigger when a user
  wants to install OpenTelemetry, connect OTel/OpenTelemetry traces to
  MultiTool, set up the OTLP exporter for MultiTool, configure service
  versioning for MultiTool, or troubleshoot why data isn't appearing in
  MultiTool. When in doubt, use this skill — it's much better to invoke it
  unnecessarily than to miss it.
---

# MultiTool OTel Setup

This skill walks the user from any starting state — fresh repo, partial OTel
setup, existing OTel pointed elsewhere, or already configured for MultiTool —
to a working tracing connection. The bulk of the work is detection: figuring
out where they are before deciding what to change.

## Invariants

These never change, regardless of language or starting state:

- **OTLP endpoint:** `https://api.multitool.run/otlp/v1/traces` (HTTP only —
  the gRPC exporter will not work).
- **Auth header:** `X-API-KEY: <value>` (uppercase, with the `X-` prefix),
  sourced from the `MULTI_API_KEY` env var. Never hardcoded. Other casings
  like `api-key` or `Api-Key` will not authenticate.
- **Mandatory resource attributes.** All three must be set on the OTel
  **Resource** (not as span attributes); MultiTool will reject or fail to
  group traces without them:
  - `service.name` — a stable identifier for the service.
  - `service.version` — must be non-empty and **change every deploy**.
    MultiTool groups traces by this value, so a static or empty value makes
    the product unusable.
  - `deployment.environment.name` — must be non-empty and resolve to
    different values across environments. Typical values: `production`,
    `staging`, `development`.

  The *source* of each value is the application's choice. Read from any env
  var the project already exports (common names: `GIT_SHA`, `BUILD_TAG`,
  `IMAGE_TAG`, `RAILS_ENV`, `NODE_ENV`, `DEPLOY_ENV`), a build-time
  constant, a CI-provided value, a framework's environment helper, or
  anything else that resolves at runtime. Step 4 of the workflow covers
  how to discover the project's existing convention before picking
  something.
- **Mandatory HTTP-server span attribute.** `http.response.status_code` must
  be set on every HTTP server span, per the OTel HTTP semantic conventions
  (https://opentelemetry.io/docs/specs/semconv/registry/attributes/http/).
  MultiTool relies on this to detect and analyze HTTP errors; spans without
  it cannot drive alerting. **Auto-instrumentation sets this automatically**
  in every supported language — prefer that path if the user has no reason
  to roll their own. Manual instrumentation has to set it explicitly on each
  server span.
- **Account-management API base:** `https://api.multitool.run/api/v1` (a
  separate URL from the OTLP ingest above).

## Handling user secrets

The user's password, the MultiTool session JWT, and the cleartext API key
must never enter the conversation transcript. Anything that lands in the
transcript is sent back to the model on every subsequent turn and can leak
through tool calls or logs.

The bundled `scripts/multitool-onboard.sh` handles signup/login and API-key
minting in the user's terminal, reading the password via `read -s` and
writing only the API key to a file the user controls. **Do not** invoke that
script via the Bash tool — it refuses to run without a TTY for exactly this
reason. Hand the invocation to the user via the `!` prefix and let them run
it themselves.

If the user already has an API key, never ask them to paste it into the chat.
Instead, ask them to add `MULTI_API_KEY=...` to their env file directly, then
verify the env var is set without reading its value (e.g.
`[ -n "${MULTI_API_KEY-}" ] && echo set`).

## Workflow

Scaffold the work with `TaskCreate` before doing anything else so the user can
see the plan and the agent doesn't lose track of which step it's on. Create
these tasks up front (adjusting wording for the user's actual phrasing):

1. Identify the application's language and runtime.
2. Determine the current OpenTelemetry state in this repo.
3. Confirm the user's MultiTool account / API key state and provision what's
   missing.
4. Apply code changes so the application sends traces to MultiTool.
5. Verify traces are arriving (or queue up troubleshooting steps if not).

Mark each task `in_progress` before working on it and `completed` immediately
after — don't batch updates. If the work expands (e.g. multiple languages, a
deploy-target-specific concern), add tasks as you discover them.

## Step 1 — Identify the language and runtime

Delegate this to a fast read-only subagent. Use the `Agent` tool with:

- `subagent_type: "Explore"`
- `model: "haiku"`
- A prompt that explicitly asks the subagent to think carefully before
  answering. The Agent tool doesn't expose a thinking-budget parameter, so
  the careful-reasoning instruction goes in the prompt itself.

Example prompt to pass:

> Identify the primary application language and runtime in this repository.
> Think carefully step-by-step before answering — polyglot repos, build-only
> manifests (e.g. a top-level `package.json` only for tooling), and
> framework-specific patterns can mislead a quick scan. Look at the
> manifests (`package.json`, `pyproject.toml`, `requirements.txt`, `go.mod`,
> `Cargo.toml`, `pom.xml`, `build.gradle`, `Gemfile`, `composer.json`,
> `*.csproj`), the entry-point file, and the most-edited source files.
> Report:
> 1. The language to instrument (one of: typescript, python, go, java, ruby,
>    rust, php, dotnet).
> 2. Confidence (high / medium / low) and the evidence you used.
> 3. Any framework or deploy target worth noting (FastAPI, Rails, Spring
>    Boot, Vercel, Lambda, etc.) — that may map to a supplementary
>    reference file.

If the subagent reports **low confidence** or **multiple candidate languages**,
ask the user to confirm with `AskUserQuestion` before proceeding.

Once the language is known, read `references/<language>/index.md` for the
detection checks and code patterns used in the rest of the workflow. If the
subagent flagged a framework or deploy target, also check whether
`references/<language>/<framework-or-target>.md` exists and read it.

## Step 2 — Determine the current OpenTelemetry state

Follow the "Detect current state" section of `references/<language>/index.md`.
The result puts the project into exactly one of these four buckets — name
the bucket back to the user so they understand the plan before any code
changes:

- **Bucket A — Not installed.** No OpenTelemetry packages in the manifest, no
  SDK initialization anywhere. Plan: install OTel + configure for MultiTool.
- **Bucket B — Installed, pointed elsewhere.** OTel is wired up and sending
  to Honeycomb / Datadog / Jaeger / a local collector / etc. **Do not
  replace the existing exporter.** Add a second OTLP HTTP exporter (wrapped
  in its own `BatchSpanProcessor`, or equivalent) pointing at MultiTool on
  the same TracerProvider — OTel supports any number of span processors and
  fan-outs the same spans to all of them. The user keeps their existing
  observability stack; MultiTool runs alongside. Also make sure all three
  mandatory resource attributes (`service.name`, `service.version`,
  `deployment.environment.name`) are present and dynamic. The language
  reference's "Adding MultiTool alongside an existing OTel backend"
  subsection shows the exact pattern.
- **Bucket C — MultiTool exporter present and fully correct.** Endpoint
  right, `X-API-KEY` header sourced from `MULTI_API_KEY`, all three
  mandatory resource attributes set on the Resource from runtime sources,
  and HTTP server spans carry `http.response.status_code` (this last bit
  is usually handled by auto-instrumentation; verify by inspecting the
  instrumentation in use). The MultiTool exporter may coexist with others
  — that's fine. Plan: confirm nothing needs to change, then jump to
  Step 5 (verify).
- **Bucket D — MultiTool exporter present but partially correct.** Bucket D
  is about the *MultiTool* exporter specifically; if other exporters
  coexist with it, leave them alone. Common Bucket D variants in roughly
  decreasing order of frequency:
  - Header is `api-key` instead of `X-API-KEY` (legacy of an earlier
    iteration of this skill).
  - `deployment.environment.name` missing from the Resource.
  - `service.version` hardcoded instead of read from a runtime source.
  - Using the gRPC exporter instead of HTTP.
  - HTTP server spans missing `http.response.status_code` (typically the
    result of hand-rolled instrumentation that didn't include it).

  Plan: apply only the missing pieces; don't rewrite working code.

If the project is in Bucket C, you can skip ahead to verification — but still
do a sanity-check pass on `service.version` and `deployment.environment.name`
resolving at runtime (hardcoded or empty values are the single most common
cause of a "configured but useless" MultiTool deployment).

## Step 3 — Provision the user's MultiTool account and API key

Use `AskUserQuestion` to figure out the user's state. Do not try to deduce it
from the repo — even users with an account often haven't created a key for
this specific service.

Question to ask:

```
Question: "Do you have a MultiTool account and API key yet?"
Header: "MultiTool access"
Options:
  - "Yes, I have a key already" — user will set MULTI_API_KEY themselves; the
    agent never reads the value.
  - "I have an account but no key for this service" — agent runs the script
    in --login mode to mint a key.
  - "I don't have a MultiTool account yet" — agent runs the script in
    --signup mode to create one and mint a key.
```

Branch on the answer:

### Branch: "Yes, I have a key already"

Ask the user to add `MULTI_API_KEY=...` to their env file (default `./.env`)
themselves. Then verify the env var is set without reading its value:

```bash
[ -n "${MULTI_API_KEY-}" ] && echo "set" || echo "unset"
```

If the user uses a different env-loading mechanism (Docker Compose, k8s
Secrets, systemd, Heroku config vars, etc.), confirm `MULTI_API_KEY` is set
there.

### Branch: "I have an account" or "I don't have an account yet"

Both branches use the bundled script. Before running it, do three things:

1. **Verify `curl` and `jq` are on PATH.** The script also checks, but a
   pre-flight check gives a clearer error if they're missing:
   ```bash
   command -v curl && command -v jq || echo "MISSING — please install before running the onboarding script"
   ```
2. **Ensure `.env` is gitignored.** Read `.gitignore`. If `.env` (or a more
   permissive pattern like `*.env` / `.env*`) is not present, add a line
   for it. If `.gitignore` doesn't exist, create one containing `.env`.
   This must happen before the script writes anything.
3. **Ask the user for the API key display name** with `AskUserQuestion`:
   ```
   Question: "What name should this API key have in the MultiTool UI?"
   Header: "API key name"
   Options:
     - "<repo-basename>-<environment>"   e.g. acme-api-prod
     - "<repo-basename>-dev"
     - "<user-supplied>"                  prompt-style; users will type their own
   ```
   The chosen string gets passed to the script via `--key-name`.

Then resolve the absolute path to the script and present the invocation to the
user. The script's path is relative to the directory containing this
SKILL.md — compute it with `realpath` so the user gets a clickable path
regardless of where the skill is installed:

```bash
realpath "$(dirname <this-SKILL.md>)/scripts/multitool-onboard.sh"
```

Then tell the user something like:

> Please run this in your terminal (the `!` prefix runs it locally with a
> real TTY, so the script can hide your password input from me):
>
> `!<resolved-path> --signup --key-name "<chosen-name>"`
>
> The script will ask for your email and password. I won't see either. When
> it's done, it'll write `MULTI_API_KEY=...` to `.env` and tell me it's
> ready.

For the "I have an account" branch, swap `--signup` for `--login`.

Wait for the user to confirm the script printed `OK: MULTI_API_KEY written to
<path>` before continuing.

## Step 4 — Apply the code changes

With the language, current state, and `MULTI_API_KEY` settled, follow the
"Point OTel at MultiTool" section of `references/<language>/index.md`.

The work varies by bucket from Step 2:

- **Bucket A (Not installed)**: follow the "Install OpenTelemetry from
  scratch" section first, then the "Point OTel at MultiTool" section. Prefer
  the auto-instrumentation path unless the user has a reason not to.
- **Bucket B (Installed, pointed elsewhere)**: skip install. Add a second
  OTLP HTTP exporter pointing at MultiTool alongside the existing exporter
  (use the language reference's "Adding MultiTool alongside an existing
  OTel backend" subsection). Do not remove or modify the existing exporter
  config. Make sure all three mandatory resource attributes are present —
  if any are missing from the existing Resource, add them (the Resource is
  shared across all exporters, so adding `deployment.environment.name`
  there will benefit the other backend too without breaking anything).
  See "Picking sources" below.
- **Bucket D (Partially correct)**: apply only the missing pieces. If
  `service.version` is hardcoded, switch it to read from whatever runtime
  source fits the project (see "Picking sources" below). If the gRPC
  exporter is in use, swap to HTTP. Don't touch anything that's already
  right.

If the existing OTel setup spans multiple files (e.g. a `tracing.ts` plus
references from `index.ts`) or you can't tell which file owns the exporter
and resource, ask before modifying. Show the user a summary of changes after
you make them.

### Picking sources for `service.version` and `deployment.environment.name`

These attributes are mandatory, but **the names of the env vars (or other
runtime sources) they read from are the application's choice**, not
something the plugin or MultiTool prescribes. The language references show
code with placeholder names like `APP_VERSION` / `APP_ENVIRONMENT` because
the code has to read from *something* — but those are defaults, not
requirements.

Before writing new env-var reads into the code, look for an existing
convention in the project:

- **CI / deploy config**: `.github/workflows/*.yml`, `Dockerfile`
  (`ENV`/`ARG`), `docker-compose.yml`, `fly.toml`, `app.yaml`, Heroku
  `Procfile`-adjacent config. CI often already exports something like
  `GIT_SHA`, `BUILD_TAG`, or `IMAGE_TAG`.
- **Framework env helpers**: `process.env.NODE_ENV`,
  `Rails.env.to_s`, `app.config.ENV`, `ASPNETCORE_ENVIRONMENT`. If one of
  these is already the source of truth for environment in the codebase,
  reuse it for `deployment.environment.name`.
- **Existing `.env` / config files** in the repo.

If something is already there, use it. If nothing is there, pick a
sensible default (`APP_VERSION` and `APP_ENVIRONMENT` work fine), explain
the choice to the user via `AskUserQuestion`, and let them swap it. Then
update the code reads to match.

In all cases, the **invariants from the top of this file** still apply:
the resolved value must be non-empty at runtime, `service.version` must
change every deploy, and `deployment.environment.name` must differ across
environments. How those values get there is up to the user.

## Step 5 — Verify

Tell the user to:

1. Set `MULTI_API_KEY` plus whatever env vars (or other sources) the code
   now reads for `service.version` and `deployment.environment.name` in the
   deployed runtime — not just a local shell session. The exact mechanism
   depends on their deployment:
   - Docker: `docker run -e MULTI_API_KEY=... -e <version-source>=... -e <env-source>=...`
   - Kubernetes: pod `env:` or a referenced Secret
   - systemd: the unit's `[Service]` section
   - Heroku / Railway / Fly / etc.: the platform's env-var UI
2. Run the service and generate some HTTP traffic (MultiTool's analysis is
   driven primarily by `http.response.status_code` on server spans, so
   traffic that exercises the HTTP layer is what produces useful data).
3. Check the MultiTool app — traces should appear within a minute or two,
   grouped by `service.version` and `deployment.environment.name`.

## Troubleshooting

**No data appearing in MultiTool:**
- Confirm `MULTI_API_KEY` is set in the runtime environment, not just a
  local shell.
- Confirm the auth header is `X-API-KEY` (uppercase, with `X-` prefix), not
  `api-key` — the old name does not authenticate.
- Verify the exporter URL is exactly `https://api.multitool.run/otlp/v1/traces`.
- Make sure the OTLP **HTTP** exporter is used (not gRPC) — see the
  language reference for the correct package.
- Check for network errors in service logs around OTel export.

**Data not grouped by version / versions mixed together:**
- Whatever source the code reads for `service.version` (env var, build
  constant, etc.) must be non-empty and change with every deploy. Verify
  the value is actually being set in the deployment environment.
- If using a git SHA, `git rev-parse` must run at build/deploy time, not be
  hardcoded to a stale value.
- Confirm `service.version` is set on the **Resource**, not as a span
  attribute.

**Data flowing but no alerts / no HTTP analysis:**
- HTTP server spans must carry `http.response.status_code`. Auto-instrumentation
  sets this; manual instrumentation has to set it explicitly. If the user
  rolled their own server spans, point them at the OTel HTTP semantic
  conventions (https://opentelemetry.io/docs/specs/semconv/registry/attributes/http/)
  and have them set the attribute when the response is written.

**Environments mixed together in the UI:**
- Whatever source the code reads for `deployment.environment.name` must be
  set per deployment and resolve to different values across environments
  (e.g. `production` vs `staging`). A missing or empty value falls back to
  the OTel default and collapses everything into one bucket.

**Exporter connection errors:**
- Check for extra quotes or whitespace in `MULTI_API_KEY`.
- Confirm the correct HTTP exporter package is installed for the language.
- Some environments block outbound HTTPS on non-standard ports — the
  MultiTool endpoint uses standard 443, so this is usually fine.

**Script failed with `stdin is not a TTY`:**
- The user invoked the onboarding script via the Bash tool or piped input.
  They need to run it directly in their terminal via the `!` prefix in
  Claude Code so password input is hidden.

**Script failed with an `Invalid…` error:**
- `InvalidPassword`: MultiTool requires 8–72 chars with upper, lower, and
  digit. Have the user try again.
- `InvalidCredentials`: wrong email or password — script does not log
  either; ask the user to retry.
- `InvalidDisplayName`: workspace or key name was empty or over 500 chars.
