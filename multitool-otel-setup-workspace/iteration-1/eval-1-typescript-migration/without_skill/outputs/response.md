# Connecting your Node.js OTel setup to MultiTool

Great — your existing setup is a solid starting point. To connect to MultiTool I'll need a couple of things from you:

1. **Your MultiTool API key** — you can find this in your MultiTool dashboard under Settings → API Keys.
2. **Do you use any versioning for your service?** For example, semantic versioning tags or git SHAs. This gets attached to traces as `service.version` and makes it much easier to correlate issues to specific deploys in MultiTool.

---

*User: Sure, my API key is `mt_test_key_abc123`. And yes, we use git SHAs for versioning.*

---

Perfect. Here's what needs to change:

## What's changing and why

**Replace `@opentelemetry/exporter-jaeger` with `@opentelemetry/exporter-trace-otlp-http`**

MultiTool (like most modern trace backends) accepts traces over the OpenTelemetry Protocol (OTLP) rather than the Jaeger Thrift wire format. The OTLP HTTP exporter is the standard way to ship traces to any OTLP-compatible endpoint, including MultiTool.

**Add `service.version` to your resource**

Since you're using git SHAs, we'll read the SHA from a `GIT_SHA` environment variable at startup and attach it to every span. That lets MultiTool group and filter traces by deploy.

**Store your API key in an environment variable**

Hard-coding secrets is a bad habit — we'll read it from `MULTITOOL_API_KEY` at runtime instead.

---

## Updated files

### `package.json`

Remove `@opentelemetry/exporter-jaeger` and add `@opentelemetry/exporter-trace-otlp-http`:

```json
{
  "name": "my-api",
  "version": "1.0.0",
  "dependencies": {
    "@opentelemetry/sdk-node": "^0.52.0",
    "@opentelemetry/resources": "^1.25.0",
    "@opentelemetry/semantic-conventions": "^1.25.0",
    "@opentelemetry/exporter-trace-otlp-http": "^0.52.0",
    "express": "^4.18.0"
  }
}
```

Run `npm install` (or `npm install @opentelemetry/exporter-trace-otlp-http`) after updating.

### `tracing.ts`

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node'
import { resourceFromAttributes } from '@opentelemetry/resources'
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'

const traceExporter = new OTLPTraceExporter({
  url: 'https://ingest.multitool.run/v1/traces',
  headers: {
    'x-api-key': process.env.MULTITOOL_API_KEY ?? '',
  },
})

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'my-api',
    [ATTR_SERVICE_VERSION]: process.env.GIT_SHA ?? 'unknown',
  }),
  traceExporter,
})

sdk.start()
```

### `index.ts`

No changes needed — it already imports `./tracing` before anything else, which is exactly right.

---

## Environment variables to set

Before starting your server, make sure these are set:

```bash
export MULTITOOL_API_KEY=mt_test_key_abc123
export GIT_SHA=$(git rev-parse HEAD)   # or however you inject the SHA in your deploy pipeline
```

In production you'd inject these through your CI/CD system or secrets manager (e.g., as a Kubernetes secret, a Render/Railway env var, etc.) rather than setting them manually.

---

## Verification

Once your server is running with the new config, make a request to `/health` (or any endpoint) to generate a trace, then check your MultiTool dashboard — you should see a trace from `my-api` appear within a few seconds. If nothing shows up after a minute:

- Double-check that `MULTITOOL_API_KEY` is set correctly in the process environment.
- Look for any startup errors in your console — the OTLP exporter will log export failures.
- Confirm the ingest URL is correct for your MultiTool account (some plans use a region-specific URL like `https://ingest.us.multitool.run/v1/traces`).

Let me know if you run into any issues!
