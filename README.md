# multitool

A Claude Code plugin that onboards services to [MultiTool](https://multitool.run)
by wiring an existing OpenTelemetry setup to the MultiTool OTLP endpoint.

## What it does

The plugin ships one skill, `otel-setup` (invoked as `/multitool:otel-setup`),
which Claude automatically
invokes when a user mentions MultiTool in the context of tracing, monitoring,
or observability. It walks the user through creating an API key, picking a
`service.version` identifier, and points the OTLP HTTP exporter at
`https://api.multitool.run/otlp/v1/traces`.

Supported languages: TypeScript/JavaScript, Python, Go, Java, Ruby, Rust, PHP, .NET.

## Installation

Install the plugin from within Claude Code by adding this repo as a plugin
marketplace, then installing the `multitool` plugin from it:

```
/plugin marketplace add wack/multitool-skill
/plugin install multitool@multitool-skill
```

The first command registers the marketplace catalog with Claude Code; the
second installs the plugin to your user scope (available across all projects).
If you already have the marketplace added but the plugin isn't showing up, run
`/plugin marketplace update multitool-skill` to refresh it.

After installing, run `/reload-plugins` to activate the plugin without
restarting Claude Code. You can manage the plugin any time by running
`/plugin` and opening the **Installed** tab.

## Layout

```
.
├── .claude-plugin/
│   └── plugin.json                 # plugin manifest
└── skills/
    └── otel-setup/
        ├── SKILL.md                # skill instructions + frontmatter
        └── references/             # per-language setup snippets
```

## Local development

Load the plugin directly from this repo without installing it:

```bash
claude --plugin-dir .
```

After editing skill files, run `/reload-plugins` inside Claude Code to pick up
changes. The skill is model-invoked, so trigger it by describing a MultiTool
onboarding task rather than invoking it by name.
