# Python — MultiTool OTel Reference

## Package to install

```bash
pip install opentelemetry-exporter-otlp-proto-http
```

## Exporter configuration

```python
import os
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

exporter = OTLPSpanExporter(
    endpoint="https://api.multitool.run/otlp/v1/traces",
    headers={"api-key": os.environ.get("MULTI_API_KEY", "")},
)
```

**Important:** Use `opentelemetry-exporter-otlp-proto-http`, not the gRPC variant
(`opentelemetry-exporter-otlp-proto-grpc`). The MultiTool endpoint is HTTP-only.

## Resource with service.version

```python
import os
from opentelemetry.sdk.resources import Resource, SERVICE_NAME, SERVICE_VERSION

resource = Resource.create({
    SERVICE_NAME: "your-service-name",         # keep existing value
    SERVICE_VERSION: os.environ.get("APP_VERSION", ""),
})
```

## Wiring it together (typical TracerProvider setup)

```python
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry import trace

provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
```

If the existing code already creates a `TracerProvider`, just add `resource=resource`
to its constructor and add the new `BatchSpanProcessor` — don't create a second provider.

## Django / Flask / FastAPI

These frameworks often configure OTel in a startup file or via middleware.

- **Django**: look in `settings.py`, `apps.py`, or a dedicated `telemetry.py`
- **Flask**: look in the application factory (`create_app`) or `app.py`
- **FastAPI**: look in `main.py` or a `lifespan` handler

## Where to find the OTel setup

Search for files importing from `opentelemetry.sdk.trace` or calling
`trace.set_tracer_provider`. Common file names: `tracing.py`, `telemetry.py`,
`instrumentation.py`, `otel.py`.
