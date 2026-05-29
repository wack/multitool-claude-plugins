# Python — MultiTool OTel Reference

## Detect current state

1. **Is OTel installed at all?** Check the project's dependency manifest:
   ```bash
   grep -E '^opentelemetry' requirements.txt pyproject.toml Pipfile setup.py 2>/dev/null
   ```
   Also check the active environment: `pip list 2>/dev/null | grep opentelemetry`.
   No matches → "Install OpenTelemetry from scratch".

2. **Where is OTel initialized?** Search for files importing
   `opentelemetry.sdk.trace` or calling `trace.set_tracer_provider`. Common
   names: `tracing.py`, `telemetry.py`, `instrumentation.py`, `otel.py`. In
   Django, also check `apps.py` and `settings.py`; in Flask, `create_app`; in
   FastAPI, `main.py` or a `lifespan` handler.

3. **Where does the exporter point today?** Inspect the `OTLPSpanExporter`'s
   `endpoint=` value.
   - `https://api.multitool.run/otlp/v1/traces` with `X-API-KEY` header from
     `MULTI_API_KEY` → already on MultiTool; jump to "Verify mandatory
     attributes when already on MultiTool".
   - Points at another backend → keep it; add a MultiTool exporter
     alongside per "Adding MultiTool alongside an existing OTel backend".
   - No exporter at all → add one per "Point OTel at MultiTool".
   - Uses `api-key` (lowercase, no `X-` prefix) in the MultiTool exporter →
     that name is wrong; the correct header is `X-API-KEY`. Fix it via
     "Point OTel at MultiTool".

## Install OpenTelemetry from scratch

### Auto-instrumentation (recommended for most apps)

The `opentelemetry-distro` bundle plus `opentelemetry-instrument` covers most
frameworks (Flask, Django, FastAPI, requests, psycopg, etc.) with no code
changes.

```bash
pip install opentelemetry-distro opentelemetry-exporter-otlp-proto-http
opentelemetry-bootstrap -a install
```

Then launch the app via the wrapper instead of `python app.py`:

```bash
opentelemetry-instrument python app.py
# Or for gunicorn/uvicorn:
opentelemetry-instrument gunicorn app:app
opentelemetry-instrument uvicorn app.main:app
```

The wrapper reads OTel config from environment variables. Set these alongside
`MULTI_API_KEY`, `APP_VERSION`, and `APP_ENVIRONMENT`:

```bash
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://api.multitool.run/otlp/v1/traces
export OTEL_EXPORTER_OTLP_HEADERS="X-API-KEY=$MULTI_API_KEY"
export OTEL_SERVICE_NAME=your-service-name
export OTEL_RESOURCE_ATTRIBUTES="service.version=$APP_VERSION,deployment.environment.name=$APP_ENVIRONMENT"
```

With this style, the code stays untouched and the "Point OTel at MultiTool" code
snippets below are not needed — env vars carry everything.

### Manual SDK bootstrap

Pick this when the user wants explicit control or auto-instrumentation pulls in
more than they want.

```bash
pip install \
  opentelemetry-api \
  opentelemetry-sdk \
  opentelemetry-exporter-otlp-proto-http
```

The "Point OTel at MultiTool" content below covers the explicit setup.

## Point OTel at MultiTool

### Package to install

```bash
pip install opentelemetry-exporter-otlp-proto-http
```

### Exporter configuration

```python
import os
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

exporter = OTLPSpanExporter(
    endpoint="https://api.multitool.run/otlp/v1/traces",
    headers={"X-API-KEY": os.environ.get("MULTI_API_KEY", "")},
)
```

**Important:** Use `opentelemetry-exporter-otlp-proto-http`, not the gRPC variant
(`opentelemetry-exporter-otlp-proto-grpc`). The MultiTool endpoint is HTTP-only.

### Resource with all three mandatory attributes

MultiTool requires `service.name`, `service.version`, and
`deployment.environment.name` on the Resource. Setting only one or two will
either make traces fail to group correctly or get rejected at ingest.

The *attribute names* are fixed, but the *source* of each value is the
application's choice — read from any env var the project already uses
(`GIT_SHA`, `BUILD_TAG`, `DEPLOY_ENV`, etc.), a build constant, or a
framework helper. The example below uses `APP_VERSION` and `APP_ENVIRONMENT`
as illustrative defaults; swap them for whatever the project already
exports.

```python
import os
from opentelemetry.sdk.resources import (
    Resource,
    SERVICE_NAME,
    SERVICE_VERSION,
    DEPLOYMENT_ENVIRONMENT,
)

resource = Resource.create({
    SERVICE_NAME: "your-service-name",                                       # pick a stable name
    SERVICE_VERSION: os.environ.get("APP_VERSION", ""),                      # or GIT_SHA, BUILD_TAG, etc.
    "deployment.environment.name": os.environ.get("APP_ENVIRONMENT", ""),    # or DEPLOY_ENV, etc.
})
```

The Python SDK's constant for the environment attribute is the older
`DEPLOYMENT_ENVIRONMENT` (no `.name` suffix); MultiTool follows the newer
OTel convention (`deployment.environment.name`), so use the string literal
to be safe — the wire value is what MultiTool reads either way.

### Wiring it together (typical TracerProvider setup)

```python
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry import trace

provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
```

If the existing code already creates a `TracerProvider`, add `resource=resource`
to its constructor and add the new `BatchSpanProcessor` — don't create a second
provider.

### Adding MultiTool alongside an existing OTel backend

If the app already adds a span processor pointing at another backend,
don't replace it — call `add_span_processor` again on the same
`TracerProvider` with a MultiTool exporter. Each processor is an
independent fan-out.

```python
import os
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

# Existing exporter (kept as-is)
existing_exporter = OTLPSpanExporter(
    endpoint="https://api.honeycomb.io/v1/traces",
    headers={"x-honeycomb-team": os.environ.get("HONEYCOMB_API_KEY", "")},
)

# New MultiTool exporter
multitool_exporter = OTLPSpanExporter(
    endpoint="https://api.multitool.run/otlp/v1/traces",
    headers={"X-API-KEY": os.environ.get("MULTI_API_KEY", "")},
)

provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(existing_exporter))   # unchanged
provider.add_span_processor(BatchSpanProcessor(multitool_exporter))  # added
trace.set_tracer_provider(provider)
```

If the project uses the `opentelemetry-instrument` wrapper (auto-instrumentation),
the wrapper attaches a single exporter configured by env vars. To run two
backends in parallel under the wrapper, use the multi-protocol form:
`OTEL_TRACES_EXPORTER=otlp` plus a custom processor that fans out. In most
cases switching to a small manual setup (above) is simpler than fighting the
wrapper's single-exporter assumption.

### Django / Flask / FastAPI

These frameworks often configure OTel in a startup file or via middleware.

- **Django**: look in `settings.py`, `apps.py`, or a dedicated `telemetry.py`
- **Flask**: look in the application factory (`create_app`) or `app.py`
- **FastAPI**: look in `main.py` or a `lifespan` handler

### `http.response.status_code` on HTTP server spans

Per OTel HTTP semconv, every HTTP server span must carry
`http.response.status_code`. MultiTool drives its HTTP error analysis off
this attribute.

- **Auto-instrumentation** for Flask, Django, FastAPI, and ASGI/WSGI sets
  this automatically. No code needed.
- **Manual server-span code** must set it explicitly:
  ```python
  span.set_attribute("http.response.status_code", response.status_code)
  ```

### Verify mandatory attributes when already on MultiTool

If the exporter is already pointed at MultiTool, double-check:
- All three resource attributes (`service.name`, `service.version`,
  `deployment.environment.name`) are set on the **Resource** (not as span
  attributes).
- `service.version` and `deployment.environment.name` each read from a
  runtime source (any env var, build constant, or framework helper —
  whatever the project uses), not hardcoded strings.
- Both resolved values are non-empty in production, and the
  `service.version` source changes every deploy.
- HTTP server spans carry `http.response.status_code`.
