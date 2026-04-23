# multitool

A Claude Code plugin that onboards services to [MultiTool](https://multitool.run)
by wiring an existing OpenTelemetry setup to the MultiTool OTLP endpoint.

## What it does

The plugin ships one skill, `multitool-otel-setup`, which Claude automatically
invokes when a user mentions MultiTool in the context of tracing, monitoring,
or observability. It walks the user through creating an API key, picking a
`service.version` identifier, and points the OTLP HTTP exporter at
`https://api.multitool.run/otlp/v1/traces`.

Supported languages: TypeScript/JavaScript, Python, Go, Java, Ruby, PHP, .NET.

## Layout

```
.
├── .claude-plugin/
│   └── plugin.json                 # plugin manifest
└── skills/
    └── multitool-otel-setup/
        ├── SKILL.md                # skill instructions + frontmatter
        ├── references/             # per-language setup snippets
        └── evals/                  # skill evaluation fixtures
```

## Local development

Load the plugin directly from this repo without installing it:

```bash
claude --plugin-dir .
```

After editing skill files, run `/reload-plugins` inside Claude Code to pick up
changes. The skill is model-invoked, so trigger it by describing a MultiTool
onboarding task rather than invoking it by name.

## Dev tooling

The `.claude/skills/skill-creator/` directory and `multitool-otel-setup-workspace/`
are used for authoring and evaluating the skill; they are not part of what the
plugin ships to users.
