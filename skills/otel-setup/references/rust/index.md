# Rust — MultiTool OTel Reference

## Detect current state

1. **Is OTel installed at all?**
   ```bash
   grep -E '^opentelemetry' Cargo.toml 2>/dev/null
   ```
   Also check `cargo metadata --format-version=1 2>/dev/null | jq -r '.packages[].name' | grep ^opentelemetry`
   if `cargo` is available. No matches → "Install OpenTelemetry from scratch".

2. **Where is OTel initialized?** Search for files that depend on
   `opentelemetry_otlp` or call `SdkTracerProvider::builder` /
   `global::set_tracer_provider`. Common file names: `tracing.rs`,
   `telemetry.rs`, `instrumentation.rs`, `otel.rs`. Also check `main.rs` or
   `lib.rs` for the initialization call.

3. **Where does the exporter point today?** Inspect the
   `SpanExporter::builder().with_endpoint(...)` call (or `OTEL_EXPORTER_OTLP_*`
   env vars).
   - `https://api.multitool.run/otlp/v1/traces` with `X-API-KEY` header from
     `MULTI_API_KEY` → already on MultiTool; jump to "Verify mandatory
     attributes when already on MultiTool".
   - Points at another backend → keep it; add a MultiTool exporter
     alongside per "Adding MultiTool alongside an existing OTel backend".
     The MultiTool exporter must use `http-proto` features even if the
     existing one uses `grpc-tonic`; the two crates can coexist.
   - No exporter at all → add one per "Point OTel at MultiTool".
   - Uses `api-key` (lowercase) in the MultiTool exporter → that name is
     wrong; the correct header is `X-API-KEY`. Fix it via "Point OTel at
     MultiTool".

## Install OpenTelemetry from scratch

Rust has no agent-style auto-instrumentation. The pattern is: pull in the
SDK + HTTP exporter crates, then add per-library tracing using crates like
`tracing-opentelemetry` (which bridges the `tracing` crate's spans into OTel)
or framework-specific middleware (`tower-http`, `actix-web-opentelemetry`).

Add to `Cargo.toml`:

```toml
[dependencies]
opentelemetry = "0.27"
opentelemetry_sdk = { version = "0.27", features = ["rt-tokio"] }
opentelemetry-otlp = { version = "0.27", features = ["http-proto", "reqwest-client"] }

# Optional but common — bridges the `tracing` crate's spans into OTel.
tracing = "0.1"
tracing-subscriber = "0.3"
tracing-opentelemetry = "0.28"
```

Then create `src/telemetry.rs` (or similar) with an `init()` function that
builds the exporter + resource + provider per "Point OTel at MultiTool" below,
and a `shutdown()` to flush on exit.

If the app uses `tokio`, prefer the `rt-tokio` feature. For a synchronous
runtime, swap to `rt-async-std` or remove the runtime feature and run the
exporter inline.

## Point OTel at MultiTool

### Packages to install

Add to `Cargo.toml`:

```toml
[dependencies]
opentelemetry = "0.27"
opentelemetry_sdk = { version = "0.27", features = ["rt-tokio"] }
opentelemetry-otlp = { version = "0.27", features = ["http-proto", "reqwest-client"] }
```

**Important:** Use the `http-proto` feature (protobuf over HTTP), not
`grpc-tonic`. The MultiTool endpoint is HTTP-only. `reqwest-client` gives you
the async HTTP client; use `reqwest-blocking-client` instead if your runtime
is synchronous.

If the project is on an older `opentelemetry` line (0.22–0.26), the same
feature names apply but the builder calls below may need minor tweaks — check
the crate's CHANGELOG for the version in use.

### Exporter configuration

```rust
use std::collections::HashMap;
use opentelemetry_otlp::{SpanExporter, WithExportConfig, WithHttpConfig};

let mut headers = HashMap::new();
headers.insert(
    "X-API-KEY".to_string(),
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
OTEL_EXPORTER_OTLP_HEADERS=X-API-KEY=your-key
OTEL_RESOURCE_ATTRIBUTES=service.name=your-service-name,service.version=your-version,deployment.environment.name=your-env
```

### Resource with all three mandatory attributes

MultiTool requires `service.name`, `service.version`, and
`deployment.environment.name` on the Resource.

The *attribute names* are fixed, but the *source* of each value is the
application's choice — read from any env var the project already uses
(`GIT_SHA`, `BUILD_TAG`, `DEPLOY_ENV`, etc.) or any other runtime source.
The example below uses `APP_VERSION` and `APP_ENVIRONMENT` as illustrative
defaults; swap them for whatever the project already exports.

```rust
use opentelemetry::KeyValue;
use opentelemetry_sdk::Resource;

let resource = Resource::builder()
    .with_attribute(KeyValue::new("service.name", "your-service-name"))     // pick a stable name
    .with_attribute(KeyValue::new(
        "service.version",
        std::env::var("APP_VERSION").unwrap_or_default(),                    // or GIT_SHA, BUILD_TAG, etc.
    ))
    .with_attribute(KeyValue::new(
        "deployment.environment.name",
        std::env::var("APP_ENVIRONMENT").unwrap_or_default(),                // or DEPLOY_ENV, etc.
    ))
    .build();
```

If `opentelemetry-semantic-conventions` is in the tree, prefer its typed
`SERVICE_NAME` / `SERVICE_VERSION` constants. The crate's deployment
environment constant uses the deprecated `deployment.environment` name, so
keep the string literal `"deployment.environment.name"` for that one.

### Wiring it together (typical TracerProvider setup)

```rust
use opentelemetry::global;
use opentelemetry_sdk::trace::SdkTracerProvider;

let provider = SdkTracerProvider::builder()
    .with_batch_exporter(exporter)
    .with_resource(resource)
    .build();

global::set_tracer_provider(provider);
```

Make sure to call `provider.shutdown()` on program exit so buffered spans are
flushed to MultiTool.

### Adding MultiTool alongside an existing OTel backend

If the app already builds an `SdkTracerProvider` with an exporter pointing
at another backend, don't replace it — add a second
`.with_batch_exporter(...)` for MultiTool. Each batch exporter is an
independent fan-out on the same provider.

```rust
use opentelemetry::global;
use opentelemetry_sdk::trace::SdkTracerProvider;
use opentelemetry_otlp::{SpanExporter, WithExportConfig, WithHttpConfig};
use std::collections::HashMap;

// Existing exporter (kept as-is; whatever crate/protocol it uses)
let existing_exporter = build_existing_exporter()?;

// New MultiTool exporter (HTTP-only)
let mut headers = HashMap::new();
headers.insert(
    "X-API-KEY".to_string(),
    std::env::var("MULTI_API_KEY").unwrap_or_default(),
);
let multitool_exporter = SpanExporter::builder()
    .with_http()
    .with_endpoint("https://api.multitool.run/otlp/v1/traces")
    .with_headers(headers)
    .build()?;

let provider = SdkTracerProvider::builder()
    .with_batch_exporter(existing_exporter)    // unchanged
    .with_batch_exporter(multitool_exporter)   // added
    .with_resource(resource)
    .build();

global::set_tracer_provider(provider);
```

### `http.response.status_code` on HTTP server spans

Per OTel HTTP semconv, every HTTP server span must carry
`http.response.status_code`.

- **Framework middlewares** like `tower-http`'s tracing layer and
  `actix-web-opentelemetry` set this automatically.
- **Hand-rolled server spans** must set it explicitly:
  ```rust
  use opentelemetry::KeyValue;

  span.set_attribute(KeyValue::new("http.response.status_code", response.status().as_u16() as i64));
  ```

### Verify mandatory attributes when already on MultiTool

If the exporter is already pointed at MultiTool, double-check that:
- All three resource attributes (`service.name`, `service.version`,
  `deployment.environment.name`) live on the **Resource** (passed via
  `.with_resource(...)`), not as span attributes.
- `service.version` and `deployment.environment.name` each read from a
  runtime source (any env var or build constant — whatever the project
  uses), not hardcoded strings.
- Both resolved values are non-empty at runtime, and the
  `service.version` source changes every deploy.
- HTTP server spans carry `http.response.status_code`.
