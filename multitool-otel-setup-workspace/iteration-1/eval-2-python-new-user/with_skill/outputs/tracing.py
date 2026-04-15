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
