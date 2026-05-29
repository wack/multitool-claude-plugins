# MultiTool Claude Plugins

A Claude Code plugin that onboards services to [MultiTool](https://multitool.run)
by setting up OpenTelemetry (installing it from scratch when needed) and
wiring it to the MultiTool OTLP endpoint.

## What it does

The plugin ships one skill, `otel-setup` (invoked as `/multitool:otel-setup`),
which Claude automatically invokes when a user mentions MultiTool in the
context of tracing, monitoring, or observability. The skill:

- Detects the application's language and the current OpenTelemetry state
  (nothing installed, installed but pointed at another backend, or already
  pointed at MultiTool).
- Helps the user create a MultiTool account and mint an API key via a bundled
  interactive script (`scripts/multitool-onboard.sh`) that hides the password
  and never exposes the cleartext key to the model.
- Makes the code changes that point the OTLP HTTP exporter at
  `https://api.multitool.run/otlp/v1/traces`, set the `X-API-KEY` header, and
  populate the three mandatory resource attributes: `service.name`,
  `service.version`, and `deployment.environment.name`.

Supported languages: TypeScript/JavaScript, Python, Go, Java, Ruby, Rust, PHP, .NET.

## Installation

Install the plugin from within Claude Code by adding this repo as a plugin
marketplace, then installing the `multitool` plugin from it:

```
/plugin marketplace add wack/multitool-claude-plugins
/plugin install multitool@multitool-claude-plugins
```

The first command registers the marketplace catalog with Claude Code; the
second installs the plugin to your user scope (available across all projects).
If you already have the marketplace added but the plugin isn't showing up, run
`/plugin marketplace update multitool-claude-plugins` to refresh it.

After installing, run `/reload-plugins` to activate the plugin without
restarting Claude Code. You can manage the plugin any time by running
`/plugin` and opening the **Installed** tab.

## Layout

```
.
├── .claude-plugin/
│   ├── plugin.json                 # plugin manifest
│   └── marketplace.json            # marketplace catalog (lists this plugin)
└── skills/
    └── otel-setup/
        ├── SKILL.md                            # skill instructions + frontmatter
        ├── scripts/
        │   └── multitool-onboard.sh           # interactive signup/login + API-key minter
        └── references/
            └── <language>/index.md            # per-language detect/install/configure guides
```

## Local development

Load the plugin directly from this repo without installing it:

```bash
claude --plugin-dir .
```

After editing skill files, run `/reload-plugins` inside Claude Code to pick up
changes. The skill is model-invoked, so trigger it by describing a MultiTool
onboarding task rather than invoking it by name.
