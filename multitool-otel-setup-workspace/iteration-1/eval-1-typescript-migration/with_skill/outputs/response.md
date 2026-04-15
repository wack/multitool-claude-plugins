# MultiTool OTel Setup — Full Interaction

---

## Step 1: Reviewing your setup

I can see you have a Node.js/TypeScript project with OpenTelemetry already configured. Here's what I found:

- **Language/runtime:** TypeScript / Node.js
- **OTel initialization:** `tracing.ts`, imported at the top of `index.ts`
- **Current exporter:** `JaegerExporter` from `@opentelemetry/exporter-jaeger`, pointing at `http://localhost:14268/api/traces`
- **SDK:** `@opentelemetry/sdk-node` with `resourceFromAttributes` and `ATTR_SERVICE_NAME` already in use

The changes needed are straightforward: swap the Jaeger exporter for the OTLP HTTP exporter pointed at MultiTool, and add `service.version` to your resource. Everything lives in `tracing.ts`, so there's only one file to touch (plus a dependency swap in `package.json`).

---

## Step 2: Two things I need from you before touching code

### API Key

Before I make the code changes, you'll need a MultiTool API key:

1. Open the MultiTool app → **Manage workspace → API keys**
2. Click **Create API key**, give it a name (e.g. `my-api-prod`), and set an expiration
3. **Copy the key value now** — you won't be able to see it again after closing the dialog

Once you have it, store it as an environment variable (don't put it in your code):

```
export MULTI_API_KEY="your-key-here"
```

Let me know when you're set and I'll make the code changes.

---

*[User responds: "Got it, my key is mt_test_key_abc123"]*

---

Great — just to confirm: store that as `MULTI_API_KEY` in your environment (not in the source code), like:

```bash
export MULTI_API_KEY="mt_test_key_abc123"
```

### Deployment Version Identifier

The other thing I need to know: how do you identify builds or deployments? This becomes the `service.version` attribute in MultiTool, which is how it groups and compares your deployments over time.

**This is important:** if `service.version` is the same across deploys (or empty), all your deployments get merged into one undifferentiated blob in MultiTool — you lose the ability to track changes version by version.

Common options:
- **Git SHA** (reliable, always unique): `export APP_VERSION=$(git rev-parse --short HEAD)`
- **Semantic version:** `export APP_VERSION="1.2.3"`
- **Container image tag:** `export APP_VERSION="$IMAGE_TAG"`
- **CI build number:** `export APP_VERSION="$BUILD_NUMBER"`

What do you use?

---

*[User responds: "We use git SHAs for versioning"]*

---

Perfect — git SHAs are a great choice. Set `APP_VERSION` at deploy time like this:

```bash
export APP_VERSION=$(git rev-parse --short HEAD)
```

Run that in whatever script or CI step kicks off your service, so the value is always the SHA of the commit being deployed.

---

## Step 3: Making the code changes

Here's what I'm changing:

### Install the new package

The Jaeger exporter gets replaced with the OTLP HTTP exporter. First, install it:

```bash
npm install @opentelemetry/exporter-trace-otlp-http
```

You can remove `@opentelemetry/exporter-jaeger` if you no longer need it:

```bash
npm uninstall @opentelemetry/exporter-jaeger
```

### Changes to `tracing.ts`

**Before:**

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node'
import { resourceFromAttributes } from '@opentelemetry/resources'
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions'
import { JaegerExporter } from '@opentelemetry/exporter-jaeger'

const traceExporter = new JaegerExporter({
  endpoint: 'http://localhost:14268/api/traces',
})

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'my-api',
  }),
  traceExporter,
})

sdk.start()
```

**After:**

```typescript
import { NodeSDK } from '@opentelemetry/sdk-node'
import { resourceFromAttributes } from '@opentelemetry/resources'
import { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } from '@opentelemetry/semantic-conventions'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'

const traceExporter = new OTLPTraceExporter({
  url: 'https://api.multitool.run/otlp/v1/traces',
  headers: {
    'api-key': process.env['MULTI_API_KEY'] ?? '',
  },
})

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'my-api',
    [ATTR_SERVICE_VERSION]: process.env['APP_VERSION'] ?? '',
  }),
  traceExporter,
})

sdk.start()
```

**Summary of changes:**
1. Replaced `JaegerExporter` import with `OTLPTraceExporter` from `@opentelemetry/exporter-trace-otlp-http`
2. Added `ATTR_SERVICE_VERSION` import alongside the existing `ATTR_SERVICE_NAME`
3. Replaced the Jaeger exporter config (local endpoint) with `OTLPTraceExporter` pointing at `https://api.multitool.run/otlp/v1/traces`, with your `MULTI_API_KEY` passed as the `api-key` header
4. Added `[ATTR_SERVICE_VERSION]: process.env['APP_VERSION'] ?? ''` to the resource attributes

### Changes to `package.json`

Replaced `@opentelemetry/exporter-jaeger` with `@opentelemetry/exporter-trace-otlp-http`:

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

`index.ts` doesn't need any changes — it just imports `./tracing` and that still works as-is.

---

## Step 4: Verifying it's working

**Before you run the service**, make sure both env vars are set in whatever environment actually runs the code — not just your local shell.

Depending on your deployment:

- **Docker:**
  ```
  docker run -e MULTI_API_KEY=mt_test_key_abc123 -e APP_VERSION=$(git rev-parse --short HEAD) ...
  ```
- **Kubernetes:** add to your pod spec's `env:` section, or reference a Secret:
  ```yaml
  env:
    - name: MULTI_API_KEY
      valueFrom:
        secretKeyRef:
          name: multitool-secrets
          key: api-key
    - name: APP_VERSION
      value: "abc1234"  # set at deploy time
  ```
- **Heroku/Railway/etc.:** set via the platform's environment variable UI

Then:

1. Start your service
2. Hit the `/health` endpoint (or generate some real traffic)
3. Open the MultiTool app — your traces should appear within a minute or two, grouped by `service.version` (your git SHA)

---

## Troubleshooting

If data doesn't show up:

- **No traces in MultiTool:** Confirm `MULTI_API_KEY` is set in the *runtime* environment (not just a local shell export). Check service logs for any errors around OTel export.
- **Data not grouped by version:** Verify `APP_VERSION` is actually being set at deploy time and is non-empty. Run `echo $APP_VERSION` in your deployment environment to confirm.
- **Exporter errors:** Make sure `@opentelemetry/exporter-trace-otlp-http` is installed (not the gRPC variant). Double-check there are no extra quotes or whitespace in `MULTI_API_KEY`.

Let me know if you run into any issues!
