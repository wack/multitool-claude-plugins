Great — I can see you have a Python/FastAPI service with OpenTelemetry already configured. Let me walk through the two things needed to connect it to MultiTool, then make the code changes.

---

## API Key

You've provided `mt_sk_abc123` — thanks. One important note: **don't put this value directly in your code**. Store it as an environment variable instead:

```
export MULTI_API_KEY="mt_sk_abc123"
```

In production (Docker, Kubernetes, etc.) you'll want to inject it through your deployment's secret/env var mechanism rather than hardcoding it anywhere in the repo.

---

## Versioning: Docker Image Tags

Using Docker image tags like `v2.1.4` as your `APP_VERSION` is a solid choice. Here's how you'd set it at deploy time:

```bash
docker run -e MULTI_API_KEY="mt_sk_abc123" -e APP_VERSION="v2.1.4" ...
```

Or in a `docker-compose.yml` or CI/CD pipeline, you'd pass the image tag as the value.

**Why this matters:** MultiTool groups traces by `service.version` to let you compare deployments side by side and track how behavior changes across releases. If `APP_VERSION` is the same (or empty) across deploys, all your data gets merged into one undifferentiated blob — you lose the ability to see which version introduced a regression or how latency changed between releases. Since your Docker image tags change with every build, they're perfect for this: each deploy will appear as a distinct version in MultiTool.

---

## Package Change

Your current setup uses the **gRPC** OTLP exporter (`opentelemetry-exporter-otlp-proto-grpc`), but MultiTool's endpoint is **HTTP-only**. You'll need to swap to the HTTP exporter:

```bash
pip install opentelemetry-exporter-otlp-proto-http
```

And update `requirements.txt` accordingly (replace `opentelemetry-exporter-otlp-proto-grpc==1.25.0` with `opentelemetry-exporter-otlp-proto-http==1.25.0`).

---

## Code Changes

Here's what I changed in `tracing.py`:

1. **Swapped the exporter import** from `otlp.proto.grpc` to `otlp.proto.http`
2. **Updated the exporter** to point at MultiTool's endpoint with the API key header
3. **Added `SERVICE_VERSION`** to the resource, sourced from the `APP_VERSION` env var

### Updated `tracing.py`

```python
import os
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry import trace

resource = Resource.create({
    SERVICE_NAME: "order-service",
    SERVICE_VERSION: os.environ.get("APP_VERSION", ""),
})

exporter = OTLPSpanExporter(
    endpoint="https://api.multitool.run/otlp/v1/traces",
    headers={"api-key": os.environ.get("MULTI_API_KEY", "")},
)

provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
```

### Updated `requirements.txt`

```
fastapi==0.111.0
uvicorn==0.30.0
opentelemetry-sdk==1.25.0
opentelemetry-instrumentation-fastapi==0.46b0
opentelemetry-exporter-otlp-proto-http==1.25.0
```

The `main.py` file doesn't need any changes — it already imports `tracing` before FastAPI, which is the correct pattern.

---

## Verifying It Works

Once you deploy with both env vars set:

```bash
docker run \
  -e MULTI_API_KEY="mt_sk_abc123" \
  -e APP_VERSION="v2.1.4" \
  your-image:v2.1.4
```

1. Generate some traffic to your service (hit `/health` or any instrumented endpoint)
2. Open the MultiTool app — traces should appear within a minute or two
3. You'll see them grouped under version `v2.1.4`; when you deploy `v2.1.5`, it will appear as a separate version for easy comparison

**If no data appears:**
- Confirm both env vars are set in the runtime environment (not just your local shell)
- Check service logs for any OTel export errors
- Verify the endpoint URL is exactly `https://api.multitool.run/otlp/v1/traces` with no trailing slash or extra path segments
