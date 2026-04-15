# TypeScript / Node.js — MultiTool OTel Reference

## Package to install

```bash
npm install @opentelemetry/exporter-trace-otlp-http
```

Your existing setup likely already has `@opentelemetry/sdk-node` and
`@opentelemetry/resources`. If `@opentelemetry/semantic-conventions` is missing,
install that too.

## Exporter configuration

```typescript
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'

const traceExporter = new OTLPTraceExporter({
  url: 'https://api.multitool.run/otlp/v1/traces',
  headers: {
    'api-key': process.env['MULTI_API_KEY'] ?? '',
  },
})
```

**Important:** Use `@opentelemetry/exporter-trace-otlp-http`, not the gRPC variant
(`@opentelemetry/exporter-trace-otlp-grpc`). The MultiTool endpoint is HTTP-only.

## Resource with service.version

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node'
import { resourceFromAttributes } from '@opentelemetry/resources'
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions'

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'your-service-name',       // keep existing value
    [ATTR_SERVICE_VERSION]: process.env['APP_VERSION'] ?? '',
  }),
  traceExporter,
})
```

If the existing setup uses the older `new Resource({...})` pattern (from
`@opentelemetry/resources`), that's fine too — just add `SERVICE_VERSION` alongside
the existing `SERVICE_NAME`:

```typescript
import { Resource } from '@opentelemetry/resources'
import {
  SemanticResourceAttributes,
} from '@opentelemetry/semantic-conventions'

const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: 'your-service-name',
  [SemanticResourceAttributes.SERVICE_VERSION]: process.env['APP_VERSION'] ?? '',
})
```

## Where to find the OTel setup

Search for files that import from `@opentelemetry/sdk-node` or instantiate `NodeSDK`.
Common file names: `tracing.ts`, `telemetry.ts`, `instrumentation.ts`, `otel.ts`.
Also check if it's called from `index.ts` or a startup file via `--require`.
