# Go — MultiTool OTel Reference

## Package to install

```bash
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp
```

## Exporter configuration

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
        "api-key": os.Getenv("MULTI_API_KEY"),
    }),
)
if err != nil {
    // handle error
}
```

**Note on the endpoint:** `otlptracehttp.WithEndpoint` takes only the host (and optional
port), not a full URL. The path goes in `WithURLPath`. The client uses HTTPS by default.
If you prefer the full-URL style, you can use `WithEndpoint("api.multitool.run")` +
`WithURLPath("/otlp/v1/traces")` as shown above, or configure via environment variables:
```
OTEL_EXPORTER_OTLP_ENDPOINT=https://api.multitool.run
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://api.multitool.run/otlp/v1/traces
OTEL_EXPORTER_OTLP_HEADERS=api-key=your-key
```

## Resource with service.version

```go
import (
    "go.opentelemetry.io/otel/sdk/resource"
    semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

res, err := resource.New(ctx,
    resource.WithAttributes(
        semconv.ServiceName("your-service-name"),       // keep existing value
        semconv.ServiceVersion(os.Getenv("APP_VERSION")),
    ),
)
```

## Wiring it together (typical TracerProvider setup)

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

## Where to find the OTel setup

Search for files importing `go.opentelemetry.io/otel/sdk/trace` or calling
`trace.NewTracerProvider`. Common file names: `tracing.go`, `telemetry.go`,
`otel.go`, `instrumentation.go`. Also check `main.go` for initialization calls.
