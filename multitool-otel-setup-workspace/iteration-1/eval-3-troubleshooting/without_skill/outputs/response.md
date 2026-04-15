# Troubleshooting: MultiTool traces missing version info and intermittent missing traces

I looked through your `tracing.ts`, `docker-compose.yml`, and `Dockerfile` and found two bugs in the deployment config. Your tracing code itself is correct — the issues are entirely in how the container is configured.

---

## Bug 1: `APP_VERSION` is never passed to the container

**The symptom:** All your traces show up in MultiTool with `service.version = "unknown"` regardless of which deployment they came from, so you can't tell old from new.

**Why it happens:** Your `tracing.ts` correctly reads the version from the environment:

```typescript
[ATTR_SERVICE_VERSION]: process.env['APP_VERSION'] ?? 'unknown',
```

But your `docker-compose.yml` never sets `APP_VERSION`:

```yaml
environment:
  - NODE_ENV=production
  - MULTI_API_KEY=${MULTI_API_KEY}
  # APP_VERSION is missing — process.env['APP_VERSION'] is always undefined
```

So `process.env['APP_VERSION']` is always `undefined`, the `?? 'unknown'` fallback always fires, and every trace from every version of your service looks identical in MultiTool.

**The fix — `docker-compose.yml`:**

```yaml
environment:
  - NODE_ENV=production
  - MULTI_API_KEY=${MULTI_API_KEY}
  - APP_VERSION=${APP_VERSION}   # add this line
```

Then set `APP_VERSION` in your shell (or a `.env` file at the project root) before running `docker compose up`:

```bash
export APP_VERSION=1.2.3
docker compose up
```

Or use a `.env` file:

```
# .env
MULTI_API_KEY=your-key-here
APP_VERSION=1.2.3
```

Docker Compose automatically reads `.env` from the same directory as `docker-compose.yml`.

---

## Bug 2: The Dockerfile has no way to bake the version at build time

This compounds Bug 1. If you build versioned images in CI (e.g., `docker build -t user-service:1.2.3 .`) and want the version embedded in the image itself rather than injected at runtime, your Dockerfile currently has no mechanism for that.

**The fix — `Dockerfile`:**

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
ARG APP_VERSION=unknown
ENV APP_VERSION=${APP_VERSION}
CMD ["node", "dist/index.js"]
```

The `ARG APP_VERSION=unknown` line declares a build argument (with `unknown` as the default if nothing is passed). The `ENV APP_VERSION=${APP_VERSION}` line promotes it to a runtime environment variable that your Node process can read.

Build with the version baked in:

```bash
docker build --build-arg APP_VERSION=1.2.3 -t user-service:1.2.3 .
```

**Note:** When you use both fixes together, the runtime env var from `docker-compose.yml` takes precedence over what was baked in at build time, which is the behavior you usually want (it lets you override without rebuilding). If you want build-time to be authoritative, just remove `APP_VERSION` from the `docker-compose.yml` environment block and rely solely on the `ARG`/`ENV` in the Dockerfile.

---

## Bug 3: Why you sometimes see no new traces at all after deploying

This is a separate issue. When `MULTI_API_KEY` is empty, your OTLP exporter sends requests to `https://api.multitool.run/otlp/v1/traces` without valid authentication. Those requests are rejected by MultiTool's ingestion endpoint, and the SDK silently discards the failed spans — you get no traces at all.

In `docker-compose.yml`, `MULTI_API_KEY` is read from the host shell via `${MULTI_API_KEY}`. If that variable isn't exported in the shell where you run `docker compose up`, it resolves to an empty string.

**How to confirm this is happening:** Run `docker compose config` and look at the resolved value of `MULTI_API_KEY`. If it's blank, that's the problem.

**The fix:** Make sure `MULTI_API_KEY` is always set before deploying. The safest approach is a `.env` file committed to your secrets manager (not to git) or injected by your CI/CD pipeline:

```
# .env (do not commit to git)
MULTI_API_KEY=your-actual-key
APP_VERSION=1.2.3
```

You can also add a guard in `tracing.ts` to fail fast at startup if the key is missing, rather than silently exporting nothing:

```typescript
const apiKey = process.env['MULTI_API_KEY']
if (!apiKey) {
  throw new Error('MULTI_API_KEY is not set — traces will not be exported. Aborting.')
}

const traceExporter = new OTLPTraceExporter({
  url: 'https://api.multitool.run/otlp/v1/traces',
  headers: {
    'api-key': apiKey,
  },
})
```

This turns a silent failure into a loud startup crash, which is much easier to diagnose.

---

## Summary of changes

| File | Change |
|---|---|
| `docker-compose.yml` | Added `- APP_VERSION=${APP_VERSION}` to the environment block |
| `Dockerfile` | Added `ARG APP_VERSION=unknown` and `ENV APP_VERSION=${APP_VERSION}` before `CMD` |

The fixed files are included alongside this document. Your `tracing.ts` and `package.json` are correct and need no changes.

---

## Workflow going forward

Once both fixes are in place, here's the recommended deployment flow:

```bash
# Set your version (e.g., from a git tag or CI variable)
export APP_VERSION=$(git describe --tags --always)
export MULTI_API_KEY=your-key-here

# Build and start
docker compose up --build
```

Or in CI, pass `APP_VERSION` as a build arg:

```bash
docker build --build-arg APP_VERSION=$CI_COMMIT_TAG -t user-service:$CI_COMMIT_TAG .
```

After this, every trace in MultiTool will carry an accurate `service.version` attribute, and you'll be able to filter and compare traces across deployments.
