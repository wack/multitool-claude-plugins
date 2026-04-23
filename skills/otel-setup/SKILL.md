---
name: otel-setup
description: >
  Configures an existing OpenTelemetry setup to send trace data to MultiTool.
  Use this skill whenever a user mentions MultiTool in the context of tracing,
  monitoring, or observability — even if they just say "I want to try MultiTool",
  "how do I use MultiTool with my service?", "how do I get started with MultiTool?",
  "how can I get MultiTool to recognize my service?", or "I want to start monitoring
  with MultiTool". Also trigger when a user wants to connect OTel/OpenTelemetry traces
  to MultiTool, set up the OTLP exporter for MultiTool, configure service versioning
  for MultiTool, or troubleshoot why data isn't appearing in MultiTool. When in doubt,
  use this skill — it's much better to invoke it unnecessarily than to miss it.
---

# MultiTool OTel Setup

Help users connect their existing OpenTelemetry instrumentation to MultiTool. The core
changes are small: point the OTLP exporter at MultiTool's endpoint, add an API key
header, and make sure each deployment has a unique `service.version` attribute.

## Step 1: Understand the Codebase

Before writing any code, explore the project to understand:

- **Language/runtime** — look for `package.json`, `go.mod`, `requirements.txt`,
  `pyproject.toml`, `pom.xml`, `build.gradle`, `Gemfile`, `*.csproj`, `composer.json`,
  `Cargo.toml`
- **Where OTel is initialized** — search for tracer provider setup, SDK initialization,
  exporter configuration. Common file names: `tracing.*`, `telemetry.*`,
  `instrumentation.*`, `otel.*`
- **What exporter is already in use** (if any) — you'll be replacing or augmenting it

Once you know the language, read the corresponding reference file from `references/`
for exact package names, import paths, and code patterns.

## Step 2: Gather What You Need

You need two things from the user. Collect them before touching any code.

### API Key

Walk them through creating one in the MultiTool UI:

> "Before I make the code changes, you'll need a MultiTool API key:
> 1. Open the MultiTool app → **Manage workspace → API keys**
> 2. Click **Create API key**, give it a name (e.g. `my-service-prod`), and set an expiration
> 3. **Copy the key value now** — you won't be able to see it again after closing the dialog
>
> Once you have it, store it as an environment variable (don't put it in your code):
> ```
> export MULTI_API_KEY="your-key-here"
> ```
> Let me know when you're set and I'll make the code changes."

### Deployment Version Identifier

This is the most important configuration detail for MultiTool to work well. MultiTool
groups traces by `service.version` to let users compare deployments and track changes
over time. **If this value is the same across deploys — or empty — all your deployments
will be merged into a single undifferentiated blob in MultiTool, which makes it nearly
useless for version-by-version monitoring.**

Ask the user how they identify builds/deploys, then help them wire it up:

- Git SHA: `export APP_VERSION=$(git rev-parse --short HEAD)`
- Semantic version: `export APP_VERSION="1.2.3"`
- Container image tag: `export APP_VERSION="$IMAGE_TAG"` (or `$DOCKER_TAG`, etc.)
- CI/CD build number: `export APP_VERSION="$BUILD_NUMBER"`

The key requirement: **the value must be non-empty and must change with every deploy.**
If they're unsure what to use, git SHA is a reliable default since it's always unique.

## Step 3: Make the Code Changes

With the language identified and the env vars decided, read `references/<language>.md`
and make two changes to their existing OTel initialization:

1. **Configure the OTLP HTTP exporter** to send to:
   - URL: `https://api.multitool.run/otlp/v1/traces`
   - Header: `api-key: <value of MULTI_API_KEY env var>`
   - Must use the **HTTP** exporter (not gRPC) — the endpoint is HTTP-only

2. **Set `service.version`** in the OTel resource to the value of the `APP_VERSION`
   env var

Make changes directly in their files. If the OTel setup spans multiple files or you're
not sure which file owns the exporter/resource config, ask before modifying. Show the
user a summary of what you changed.

If a package needs to be installed first, tell them the install command before proceeding.

## Step 4: Verify It's Working

After the changes, remind the user to:

1. **Set both env vars in their runtime** (not just a local shell session). The exact
   method depends on their deployment:
   - Docker: `docker run -e MULTI_API_KEY=... -e APP_VERSION=...`
   - Kubernetes: add to the pod's `env:` section or reference a Secret
   - systemd: add to the unit's `[Service]` section
   - Heroku/Railway/etc.: set via the platform's environment variable UI
2. Run their service and generate some traffic
3. Check the MultiTool app — traces should appear within a minute or two, grouped
   by `service.version`

## Troubleshooting

If the user reports problems after setup:

**No data appearing in MultiTool:**
- Confirm `MULTI_API_KEY` is set in the runtime environment, not just a local shell
- Verify the exporter URL is exactly `https://api.multitool.run/otlp/v1/traces`
- Make sure the OTLP **HTTP** exporter is used (not gRPC) — see the reference file
  for the correct package
- Check for network errors in service logs around OTel export

**Data not grouped by version / versions mixed together:**
- `APP_VERSION` must be non-empty and change with every deploy — verify the value
  is actually being set in the deployment environment
- If using git SHA, the `git rev-parse` must run at build/deploy time, not be
  hardcoded to a stale value
- Confirm `service.version` is set on the **resource**, not as a span attribute

**Exporter connection errors:**
- Double-check there are no extra quotes or whitespace in `MULTI_API_KEY`
- Confirm the correct package is installed for your language (see reference file)
- Some environments block outbound HTTPS on non-standard ports — the MultiTool
  endpoint uses standard port 443, so this is usually fine, but worth checking
