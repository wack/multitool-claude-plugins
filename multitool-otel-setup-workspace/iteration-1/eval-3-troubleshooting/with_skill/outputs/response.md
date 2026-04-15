# Diagnosing Your MultiTool Tracing Issues

I looked at your four files — `tracing.ts`, `package.json`, `Dockerfile`, and `docker-compose.yml` — and the root cause of both problems is the same: **`APP_VERSION` is never passed into your running container**.

---

## What your code is doing (correctly)

Your `tracing.ts` is written exactly right:

```typescript
[ATTR_SERVICE_VERSION]: process.env['APP_VERSION'] ?? 'unknown',
```

It reads `APP_VERSION` from the environment and falls back to `'unknown'` when the variable isn't set. Same story for `MULTI_API_KEY` — the code reads it from the environment correctly.

---

## Where things break down: the deployment config

### Problem 1: `APP_VERSION` is missing from `docker-compose.yml`

Your current `docker-compose.yml` passes `NODE_ENV` and `MULTI_API_KEY` into the container, but not `APP_VERSION`:

```yaml
environment:
  - NODE_ENV=production
  - MULTI_API_KEY=${MULTI_API_KEY}
  # APP_VERSION is never forwarded here
```

This means every container you launch — regardless of which version of the code is inside — will have `APP_VERSION` unset. Your `tracing.ts` fallback kicks in and sends `service.version = "unknown"` for every single deploy.

**Effect on MultiTool:** All your deployments are tagged `"unknown"` and land in the same version bucket. When you pushed your new version yesterday, its traces merged right in with the old version's traces because both were labeled `"unknown"`. MultiTool has no way to separate them.

### Problem 2: This also explains the "no new traces" symptom

Look at what happens to `MULTI_API_KEY` when it isn't set in the host shell before you run `docker compose up`:

```yaml
- MULTI_API_KEY=${MULTI_API_KEY}
```

Docker Compose expands `${MULTI_API_KEY}` from the **host shell environment at the time you run `docker compose up`**. If that variable isn't exported in your shell session, Docker passes an empty string into the container. Your `tracing.ts` then constructs the exporter with a blank `api-key` header, and MultiTool's API rejects the requests silently (no auth = no data).

This is likely the cause of "sometimes I see no new traces at all after deploying" — it happens when `MULTI_API_KEY` isn't in scope in the shell where you run Compose. The `APP_VERSION` issue has the same failure mode: if you forget to set it in the host shell, the container gets an empty value and falls through to `'unknown'`.

---

## The fixes

### Fix 1: Add `APP_VERSION` to `docker-compose.yml`

```yaml
version: '3.8'
services:
  user-service:
    build: .
    ports:
      - '4000:4000'
    environment:
      - NODE_ENV=production
      - MULTI_API_KEY=${MULTI_API_KEY}
      - APP_VERSION=${APP_VERSION}   # add this line
```

I've saved this as the updated `docker-compose.yml` in the output directory.

### Fix 2: Set both variables before running Compose

Before every deploy, make sure both are exported in your shell:

```bash
export MULTI_API_KEY="your-key-here"
export APP_VERSION=$(git rev-parse --short HEAD)   # or your image tag, semver, etc.
docker compose up -d
```

Using the git short SHA for `APP_VERSION` is a reliable default — it's always unique per commit, so every deploy will get its own version label in MultiTool automatically.

### Fix 3 (recommended): Use a `.env` file so you never forget

Create a `.env` file alongside `docker-compose.yml` (and add it to `.gitignore`):

```
MULTI_API_KEY=your-key-here
APP_VERSION=
```

Then in your deploy script, write the version in before starting Compose:

```bash
echo "APP_VERSION=$(git rev-parse --short HEAD)" >> .env
docker compose up -d
```

Docker Compose loads `.env` automatically, so both variables will always be present.

---

## Why the Dockerfile doesn't need to change

The `Dockerfile` runs `npm run build` at image-build time. `APP_VERSION` is a runtime identifier (which commit/image is running right now), not something you want baked into the image at build time — otherwise every container from the same image would always report the same version regardless of when or how it was deployed. Passing it via `docker-compose.yml` environment at container start time is exactly the right pattern.

---

## Summary of changes

| File | Change |
|---|---|
| `docker-compose.yml` | Added `APP_VERSION=${APP_VERSION}` to the `environment` block |
| `Dockerfile` | No change needed |
| `tracing.ts` | No change needed — this code is correct |
| `package.json` | No change needed — all required packages are present |

After making this change and deploying with `APP_VERSION` set to the new git SHA, you'll see your traces split into two separate version groups in MultiTool: one for the previous deploy and one for the new one.
