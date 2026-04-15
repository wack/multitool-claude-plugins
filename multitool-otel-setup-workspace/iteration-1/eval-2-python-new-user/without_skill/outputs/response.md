# Connecting your Python/FastAPI OTel setup to MultiTool

Here is everything you need to route your traces to MultiTool alongside your existing internal collector.

---

## What changes and why

| | Before | After |
|---|---|---|
| **Exporter(s)** | Single gRPC exporter → internal collector | gRPC exporter (unchanged) + HTTP exporter → MultiTool |
| **Resource attributes** | `service.name` only | `service.name` + `service.version` (from `APP_VERSION`) |
| **FastAPI instrumentation** | Not wired up | `FastAPIInstrumentor.instrument_app(app)` added |
| **New dependency** | — | `opentelemetry-exporter-otlp-proto-http` |

MultiTool's ingest endpoint speaks **OTLP HTTP** (not gRPC), which is why you need the HTTP exporter package in addition to the gRPC one you already have.

---

## Updated files

### requirements.txt

Add `opentelemetry-exporter-otlp-proto-http==1.25.0` (matches your existing SDK version):

```
fastapi==0.111.0
uvicorn==0.30.0
opentelemetry-sdk==1.25.0
opentelemetry-instrumentation-fastapi==0.46b0
opentelemetry-exporter-otlp-proto-grpc==1.25.0
opentelemetry-exporter-otlp-proto-http==1.25.0
```

### tracing.py

```python
import os
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter as OTLPHTTPSpanExporter
from opentelemetry import trace

# Read config from environment
MULTITOOL_API_KEY = os.environ.get("MULTITOOL_API_KEY", "")
APP_VERSION = os.environ.get("APP_VERSION", "unknown")

resource = Resource.create({
    SERVICE_NAME: "order-service",
    "service.version": APP_VERSION,
})

provider = TracerProvider(resource=resource)

# Original internal collector (gRPC) — keep if you still want it
exporter = OTLPSpanExporter(
    endpoint="http://otel-collector:4317",
)
provider.add_span_processor(BatchSpanProcessor(exporter))

# MultiTool exporter (OTLP HTTP)
multitool_exporter = OTLPHTTPSpanExporter(
    endpoint="https://ingest.multitool.run/v1/traces",
    headers={"x-api-key": MULTITOOL_API_KEY},
)
provider.add_span_processor(BatchSpanProcessor(multitool_exporter))

trace.set_tracer_provider(provider)
```

### main.py

Wire up `FastAPIInstrumentor` so every route automatically gets a span:

```python
import tracing  # noqa: F401 - must be imported before FastAPI
from fastapi import FastAPI
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

app = FastAPI()

# Instrument FastAPI so all routes produce spans automatically
FastAPIInstrumentor.instrument_app(app)

@app.get("/health")
def health():
    return {"status": "ok"}
```

---

## Environment variables

Set these in your Docker run command, Compose file, or Kubernetes deployment:

```bash
MULTITOOL_API_KEY=mt_sk_abc123
APP_VERSION=v2.1.4        # or whatever your image tag is at deploy time
```

**Docker Compose example:**
```yaml
services:
  order-service:
    image: order-service:${APP_VERSION}
    environment:
      - MULTITOOL_API_KEY=mt_sk_abc123
      - APP_VERSION=${APP_VERSION}
```

**Docker run example:**
```bash
docker run \
  -e MULTITOOL_API_KEY=mt_sk_abc123 \
  -e APP_VERSION=v2.1.4 \
  order-service:v2.1.4
```

**Kubernetes Deployment example:**
```yaml
env:
  - name: MULTITOOL_API_KEY
    valueFrom:
      secretKeyRef:
        name: multitool-secrets
        key: api-key
  - name: APP_VERSION
    value: "v2.1.4"
```

> **Security note:** Store `MULTITOOL_API_KEY` as a secret (Kubernetes Secret, Docker Swarm secret, AWS Secrets Manager, etc.) rather than hardcoding it in your image or Compose file.

---

## How it works

1. Both `BatchSpanProcessor` instances are registered on the same `TracerProvider`. OpenTelemetry fans out every finished span to all registered processors, so your existing internal collector keeps receiving data unchanged.

2. The HTTP exporter sends spans to MultiTool's ingest endpoint with your API key in the `x-api-key` header. MultiTool uses the `service.name` attribute (`"order-service"`) to identify your service in the UI, and `service.version` to let you filter/compare traces by deploy version.

3. `FastAPIInstrumentor.instrument_app(app)` must be called after the `TracerProvider` is registered (which happens at import time via `import tracing` at the top of `main.py`) — your existing import order already handles this correctly.

---

## Verifying it works

After deploying, send a test request:

```bash
curl http://localhost:8000/health
```

Then check the MultiTool dashboard. You should see a trace for `GET /health` on the `order-service` service within a few seconds. If traces don't appear after a minute or two:

1. Check that `MULTITOOL_API_KEY` is set correctly in the container (`docker exec <container> env | grep MULTITOOL`).
2. Check application logs for export errors — `BatchSpanProcessor` logs failures at the WARNING level.
3. Verify outbound HTTPS (port 443) to `ingest.multitool.run` is not blocked by your network/firewall.
4. Confirm `APP_VERSION` is set — if it resolves to `"unknown"` you'll still get traces, but version filtering in MultiTool won't work.
