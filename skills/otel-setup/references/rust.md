# Rust — MultiTool OTel Reference

## Packages to install

Add to `Cargo.toml`:

```toml
[dependencies]
opentelemetry = "0.27"
opentelemetry_sdk = { version = "0.27", features = ["rt-tokio"] }
opentelemetry-otlp = { version = "0.27", features = ["http-proto", "reqwest-client"] }
```

**Important:** Use the `http-proto` feature (protobuf over HTTP), not `grpc-tonic`.
The MultiTool endpoint is HTTP-only. `reqwest-client` gives you the async HTTP
client; use `reqwest-blocking-client` instead if your runtime is synchronous.

If the project is on an older `opentelemetry` line (0.22–0.26), the same feature
names apply but the builder calls below may need minor tweaks — check the
crate's CHANGELOG for the version in use.

## Exporter configuration

```rust
use std::collections::HashMap;
use opentelemetry_otlp::{SpanExporter, WithExportConfig, WithHttpConfig};

let mut headers = HashMap::new();
headers.insert(
    "api-key".to_string(),
    std::env::var("MULTI_API_KEY").unwrap_or_default(),
);

let exporter = SpanExporter::builder()
    .with_http()
    .with_endpoint("https://api.multitool.run/otlp/v1/traces")
    .with_headers(headers)
    .build()?;
```

If the existing code configures the exporter via env vars, these work too:

```
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://api.multitool.run/otlp/v1/traces
OTEL_EXPORTER_OTLP_HEADERS=api-key=your-key
```

## Resource with service.version

```rust
use opentelemetry::KeyValue;
use opentelemetry_sdk::Resource;

let resource = Resource::builder()
    .with_attribute(KeyValue::new("service.name", "your-service-name"))
    .with_attribute(KeyValue::new(
        "service.version",
        std::env::var("APP_VERSION").unwrap_or_default(),
    ))
    .build();
```

If the crate `opentelemetry-semantic-conventions` is already a dependency, prefer
its typed constants (`SERVICE_NAME`, `SERVICE_VERSION`) over raw strings.

## Wiring it together (typical TracerProvider setup)

```rust
use opentelemetry::global;
use opentelemetry_sdk::trace::SdkTracerProvider;

let provider = SdkTracerProvider::builder()
    .with_batch_exporter(exporter)
    .with_resource(resource)
    .build();

global::set_tracer_provider(provider);
```

If the existing code already builds an `SdkTracerProvider`, just swap in the new
exporter and add `service.version` to the resource — don't create a second provider.

Make sure to call `provider.shutdown()` on program exit so buffered spans are
flushed to MultiTool.

## Where to find the OTel setup

Search for files that depend on `opentelemetry_otlp` or call
`SdkTracerProvider::builder` / `global::set_tracer_provider`. Common file names:
`tracing.rs`, `telemetry.rs`, `instrumentation.rs`, `otel.rs`. Also check
`main.rs` or `lib.rs` for the initialization call, and inspect `Cargo.toml` to
confirm the `opentelemetry*` crate versions in use.
