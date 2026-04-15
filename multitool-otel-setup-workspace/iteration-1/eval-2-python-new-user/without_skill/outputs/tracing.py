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
