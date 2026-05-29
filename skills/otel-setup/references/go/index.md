# Go — MultiTool OTel Reference

## Detect current state

1. **Is OTel installed at all?**
   ```bash
   grep -E 'go.opentelemetry.io/otel' go.mod 2>/dev/null
   ```
   No matches → "Install OpenTelemetry from scratch".

2. **Where is OTel initialized?** Search for files importing
   `go.opentelemetry.io/otel/sdk/trace` or calling `trace.NewTracerProvider`.
   Common file names: `tracing.go`, `telemetry.go`, `otel.go`,
   `instrumentation.go`. Also check `main.go` for the initialization call.

3. **Where does the exporter point today?** Look at `otlptracehttp.WithEndpoint`
   and `WithURLPath` (or the equivalent grpc client).
   - Endpoint `api.multitool.run` + path `/otlp/v1/traces` with the
     `X-API-KEY` header from `MULTI_API_KEY` → already on MultiTool; jump to
     "Verify mandatory attributes when already on MultiTool".
   - Points at another backend (Honeycomb, Datadog, Jaeger, default OTLP
     collector, etc.) → keep it; add a MultiTool exporter alongside per
     "Adding MultiTool alongside an existing OTel backend".
   - No exporter at all → add one per "Point OTel at MultiTool".
   - Uses `api-key` (lowercase) in the MultiTool exporter → that name is
     wrong; the correct header is `X-API-KEY`. Fix it via "Point OTel at
     MultiTool".

## Install OpenTelemetry from scratch

Unlike Java/Python/Node, Go doesn't have an officially-supported agent-based
auto-instrumentation path for production. Set up the SDK manually and reach
for `otelhttp`-style instrumenting wrappers around the HTTP/gRPC libraries
the app uses.

```bash
go get \
  go.opentelemetry.io/otel \
  go.opentelemetry.io/otel/sdk \
  go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp \
  go.opentelemetry.io/otel/semconv/v1.26.0
```

Create `tracing.go` (or `telemetry.go`) with an `Init(ctx) (shutdown func(...) error, err error)`
function that the app calls from `main`. The body is exactly what "Point OTel
at MultiTool" describes below — exporter + resource + provider, then
`otel.SetTracerProvider(tp)`.

For per-library spans, wrap the libraries the user actually uses, e.g.:

- `net/http`: `go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp`
- `database/sql`: `github.com/XSAM/otelsql`
- gRPC: `go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc`

Ask the user which libraries they want instrumented and pull just those.

## Point OTel at MultiTool

### Package to install

```bash
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp
```

### Exporter configuration

```go
import (
    "context"
    "os"

    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
)

exporter, err := otlptracehttp.New(ctx,
    otlptracehttp.WithEndpoint("api.multitool.run"),   // no scheme — the client adds https://
    otlptracehttp.WithURLPath("/otlp/v1/traces"),
    otlptracehttp.WithHeaders(map[string]string{
        "X-API-KEY": os.Getenv("MULTI_API_KEY"),
    }),
)
if err != nil {
    // handle error
}
```

**Note on the endpoint:** `otlptracehttp.WithEndpoint` takes only the host (and
optional port), not a full URL. The path goes in `WithURLPath`. The client uses
HTTPS by default. If you prefer environment-variable configuration:

```
OTEL_EXPORTER_OTLP_ENDPOINT=https://api.multitool.run
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://api.multitool.run/otlp/v1/traces
OTEL_EXPORTER_OTLP_HEADERS=X-API-KEY=your-key
OTEL_RESOURCE_ATTRIBUTES=service.name=your-service-name,service.version=your-version,deployment.environment.name=your-env
```

### Resource with all three mandatory attributes

MultiTool requires `service.name`, `service.version`, and
`deployment.environment.name` on the Resource.

The *attribute names* are fixed, but the *source* of each value is the
application's choice — read from any env var the project already exports
(`GIT_SHA`, `BUILD_TAG`, `IMAGE_TAG`, `DEPLOY_ENV`, etc.), a build-time
constant, or anything else that resolves at runtime. The example below
uses `APP_VERSION` and `APP_ENVIRONMENT` as illustrative defaults; swap
them for whatever the project already exports.

```go
import (
    "go.opentelemetry.io/otel/sdk/resource"
    semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
    "go.opentelemetry.io/otel/attribute"
)

res, err := resource.New(ctx,
    resource.WithAttributes(
        semconv.ServiceName("your-service-name"),                                       // pick a stable name
        semconv.ServiceVersion(os.Getenv("APP_VERSION")),                               // or GIT_SHA, BUILD_TAG, etc.
        attribute.String("deployment.environment.name", os.Getenv("APP_ENVIRONMENT")),  // or DEPLOY_ENV, etc.
    ),
)
```

The `semconv` package's `DeploymentEnvironment` helper uses the older
attribute name (`deployment.environment`); use the explicit string literal
to match MultiTool's expected name (`deployment.environment.name`).

### Wiring it together (typical TracerProvider setup)

```go
import (
    "go.opentelemetry.io/otel/sdk/trace"
)

tp := trace.NewTracerProvider(
    trace.WithBatcher(exporter),
    trace.WithResource(res),
)
otel.SetTracerProvider(tp)
```

Don't forget `defer tp.Shutdown(ctx)` so buffered spans flush to MultiTool on
exit.

### Adding MultiTool alongside an existing OTel backend

If the app already sends spans to another backend (Honeycomb, Datadog,
Jaeger, a local collector, etc.), don't replace that exporter — add a
second `WithBatcher` for MultiTool. Each `WithBatcher` is an independent
fan-out: same spans, different sinks.

```go
import (
    "go.opentelemetry.io/otel/sdk/trace"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
)

// Existing exporter (kept as-is)
existingExporter, _ := otlptracehttp.New(ctx,
    otlptracehttp.WithEndpoint("api.honeycomb.io"),
    otlptracehttp.WithHeaders(map[string]string{
        "x-honeycomb-team": os.Getenv("HONEYCOMB_API_KEY"),
    }),
)

// New MultiTool exporter
multitoolExporter, _ := otlptracehttp.New(ctx,
    otlptracehttp.WithEndpoint("api.multitool.run"),
    otlptracehttp.WithURLPath("/otlp/v1/traces"),
    otlptracehttp.WithHeaders(map[string]string{
        "X-API-KEY": os.Getenv("MULTI_API_KEY"),
    }),
)

tp := trace.NewTracerProvider(
    trace.WithBatcher(existingExporter),    // unchanged
    trace.WithBatcher(multitoolExporter),   // added
    trace.WithResource(res),
)
otel.SetTracerProvider(tp)
```

The resource attributes apply to spans going to *all* backends. If the
other backend doesn't yet have `deployment.environment.name` on its
resource, adding it now is harmless — that backend simply gets an extra
attribute.

### `http.response.status_code` on HTTP server spans

Per OTel HTTP semconv, every HTTP server span must carry
`http.response.status_code`. MultiTool's HTTP error analysis depends on it.

- **`otelhttp.NewHandler` and `otelgin.Middleware`** (and other framework
  middlewares from `go.opentelemetry.io/contrib`) set this automatically.
- **Hand-rolled server spans** must set it after the response is written:
  ```go
  import semconv "go.opentelemetry.io/otel/semconv/v1.26.0"

  span.SetAttributes(semconv.HTTPResponseStatusCode(statusCode))
  ```

### Verify mandatory attributes when already on MultiTool

If the exporter is already pointed at MultiTool, double-check that:
- All three resource attributes (`service.name`, `service.version`,
  `deployment.environment.name`) live on the **Resource** (passed via
  `trace.WithResource`), not as span attributes.
- `service.version` and `deployment.environment.name` each read from a
  runtime source (any env var or build constant — whatever the project
  uses), not hardcoded strings.
- Both resolved values are non-empty in the deployed binary, and the
  `service.version` source changes every deploy.
- HTTP server spans carry `http.response.status_code` (verify a real span in
  the MultiTool UI).
