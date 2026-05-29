# TypeScript / Node.js — MultiTool OTel Reference

This reference covers three states the project can be in. Identify the state first, then
jump to the matching section.

## Detect current state

Run these checks in order — they tell you which section below to read next.

1. **Is OTel installed at all?**
   ```bash
   jq -r '.dependencies // {}, .devDependencies // {}' package.json 2>/dev/null \
     | grep -E '"@opentelemetry/' | head
   ```
   No matches → "Install OpenTelemetry from scratch". Matches → continue.

2. **Where is OTel initialized?** Look for files that import `@opentelemetry/sdk-node`
   or instantiate `NodeSDK`. Common names: `tracing.ts`, `telemetry.ts`,
   `instrumentation.ts`, `otel.ts`. Also check `package.json` `scripts` for
   `--require ./tracing.js` or `NODE_OPTIONS=--require ...`.

3. **Where does the exporter point today?** In whatever file owns the SDK, look
   at the `OTLPTraceExporter` (or `OTLPExporter`) `url:` / `endpoint:` value.
   - Already `https://api.multitool.run/otlp/v1/traces` with the `X-API-KEY`
     header sourced from `MULTI_API_KEY` → already on MultiTool; jump to
     "Verify mandatory attributes when already on MultiTool".
   - Pointed at another backend (Honeycomb, Datadog, Jaeger, default OTLP
     collector, etc.) → keep it; add a MultiTool exporter alongside per
     "Adding MultiTool alongside an existing OTel backend".
   - Missing entirely → use "Point OTel at MultiTool" to add it.
   - Uses `api-key` (lowercase, no `X-` prefix) in the MultiTool exporter →
     that name is wrong; the correct header is `X-API-KEY`. Fix it via
     "Point OTel at MultiTool".

## Install OpenTelemetry from scratch

There are two paths. Pick auto-instrumentation unless the user has a reason not to.

### Auto-instrumentation (recommended for most apps)

Captures HTTP, database, and framework spans automatically with no code changes
beyond an entry-point hook.

```bash
npm install --save \
  @opentelemetry/api \
  @opentelemetry/sdk-node \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-http \
  @opentelemetry/resources \
  @opentelemetry/semantic-conventions
```

Create `tracing.ts` at the project root (the file that "Point OTel at MultiTool"
will fill out). Then load it before the app starts — easiest via NODE_OPTIONS:

```json
// package.json
{
  "scripts": {
    "start": "node --require ./tracing.js dist/index.js"
  }
}
```

For TypeScript-only dev: `ts-node --require ./tracing.ts src/index.ts` (or use
`tsx`/`esbuild-register` to match the project's runner).

### Manual SDK bootstrap

Use this when the user wants explicit control or auto-instrumentation pulls in
more than they want. Install the same packages minus `auto-instrumentations-node`.
The "Wiring it together" subsection of "Point OTel at MultiTool" below shows
the explicit setup.

## Point OTel at MultiTool

Two changes go in the file that owns the OTel SDK setup (`tracing.ts` or
equivalent).

### Package to install

If not already present (it usually is once `@opentelemetry/sdk-node` is in the
tree):

```bash
npm install @opentelemetry/exporter-trace-otlp-http
```

### Exporter configuration

```typescript
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'

const traceExporter = new OTLPTraceExporter({
  url: 'https://api.multitool.run/otlp/v1/traces',
  headers: {
    'X-API-KEY': process.env['MULTI_API_KEY'] ?? '',
  },
})
```

**Important:** Use `@opentelemetry/exporter-trace-otlp-http`, not the gRPC variant
(`@opentelemetry/exporter-trace-otlp-grpc`). The MultiTool endpoint is HTTP-only.

### Resource with all three mandatory attributes

MultiTool requires `service.name`, `service.version`, and
`deployment.environment.name` on the Resource. Setting only one or two will
either make traces fail to group correctly or get rejected at ingest.

The *attribute names* are fixed, but the *source* of each value is the
application's choice — read from any env var the project already uses
(`GIT_SHA`, `BUILD_TAG`, `NODE_ENV`, etc.), a build constant, or anything
else that resolves at runtime. The example below uses `APP_VERSION` and
`APP_ENVIRONMENT` as illustrative defaults; swap them for whatever the
project already exports.

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node'
import { resourceFromAttributes } from '@opentelemetry/resources'
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
  ATTR_DEPLOYMENT_ENVIRONMENT_NAME,
} from '@opentelemetry/semantic-conventions'
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'your-service-name',                          // pick a stable name
    [ATTR_SERVICE_VERSION]: process.env['APP_VERSION'] ?? '',          // or GIT_SHA, BUILD_TAG, etc.
    [ATTR_DEPLOYMENT_ENVIRONMENT_NAME]: process.env['APP_ENVIRONMENT'] ?? '',  // or NODE_ENV, DEPLOY_ENV, etc.
  }),
  traceExporter,
  instrumentations: [getNodeAutoInstrumentations()],   // omit if going manual
})

sdk.start()
```

If `ATTR_DEPLOYMENT_ENVIRONMENT_NAME` isn't exported by the installed
`@opentelemetry/semantic-conventions` version, use the string literal
`'deployment.environment.name'` — the wire format is the same.

If the existing setup uses the older `new Resource({...})` pattern, just add
all three attributes:

```typescript
import { Resource } from '@opentelemetry/resources'
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions'

const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: 'your-service-name',
  [SemanticResourceAttributes.SERVICE_VERSION]: process.env['APP_VERSION'] ?? '',
  'deployment.environment.name': process.env['APP_ENVIRONMENT'] ?? '',
})
```

### Adding MultiTool alongside an existing OTel backend

If the app already pushes spans to another backend, don't replace the
exporter — attach a second `BatchSpanProcessor` for MultiTool on the same
`NodeSDK` (or `BasicTracerProvider`). Each processor is an independent
fan-out.

When using `NodeSDK`, swap the single `traceExporter` for an explicit
`spanProcessors` array:

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node'
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'

// Existing exporter (kept as-is)
const existingExporter = new OTLPTraceExporter({
  url: 'https://api.honeycomb.io/v1/traces',
  headers: { 'x-honeycomb-team': process.env['HONEYCOMB_API_KEY'] ?? '' },
})

// New MultiTool exporter
const multitoolExporter = new OTLPTraceExporter({
  url: 'https://api.multitool.run/otlp/v1/traces',
  headers: { 'X-API-KEY': process.env['MULTI_API_KEY'] ?? '' },
})

const sdk = new NodeSDK({
  resource,                                                       // unchanged
  spanProcessors: [
    new BatchSpanProcessor(existingExporter),                     // unchanged
    new BatchSpanProcessor(multitoolExporter),                    // added
  ],
  instrumentations: [getNodeAutoInstrumentations()],
})
sdk.start()
```

If the existing setup uses a `BasicTracerProvider` directly (rather than
`NodeSDK`), call `provider.addSpanProcessor(new BatchSpanProcessor(...))`
once per exporter.

### `http.response.status_code` on HTTP server spans

Per the OTel HTTP semantic conventions, every HTTP server span must carry
`http.response.status_code`. MultiTool uses this to drive HTTP error
analysis — spans without it can't be alerted on.

- **Auto-instrumentation** (`@opentelemetry/auto-instrumentations-node` or
  `@opentelemetry/instrumentation-http`) sets this automatically. No code is
  needed.
- **Manual server-span code** must set it explicitly when the response is
  written:
  ```typescript
  import { ATTR_HTTP_RESPONSE_STATUS_CODE } from '@opentelemetry/semantic-conventions'

  span.setAttribute(ATTR_HTTP_RESPONSE_STATUS_CODE, res.statusCode)
  ```

### Verify mandatory attributes when already on MultiTool

If the project was already pointed at MultiTool, double-check that:
- All three resource attributes are set on the **Resource** (not as span
  attributes).
- `service.version` reads from a runtime source (any env var or build
  constant — whatever the project uses) and not a hardcoded string.
- `deployment.environment.name` reads from a runtime source and not a
  hardcoded string.
- Both resolved values are non-empty in the deployed runtime, and the
  `service.version` source changes every deploy.
- HTTP server spans carry `http.response.status_code` (look at a real span
  in the MultiTool UI or in the project's local span exporter to confirm).
