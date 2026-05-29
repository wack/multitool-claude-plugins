# .NET / C# — MultiTool OTel Reference

## Detect current state

1. **Is OTel installed at all?**
   ```bash
   grep -rE '<PackageReference\s+Include="OpenTelemetry' --include='*.csproj' . 2>/dev/null
   ```
   Also check for an `OTEL_DOTNET_AUTO_HOME` env var or
   `OpenTelemetry.AutoInstrumentation` references — that's the auto-instrumentation
   profile. No signal → "Install OpenTelemetry from scratch".

2. **Where is OTel initialized?** Search for `AddOpenTelemetry()`,
   `TracerProvider`, or `Sdk.CreateTracerProviderBuilder`. Common locations:
   `Program.cs`, `Startup.cs`, or a dedicated `TelemetryExtensions.cs` /
   `OpenTelemetryConfig.cs`. With the auto-instrumentation profile, there's no
   SDK code — all config lives in env vars.

3. **Where does the exporter point today?** Inspect the `AddOtlpExporter`
   options block — specifically `options.Endpoint` and `options.Headers`.
   - `https://api.multitool.run/api/otlp/v1/traces` with `X-API-KEY` header from
     `MULTI_API_KEY` → already on MultiTool; jump to "Verify mandatory
     attributes when already on MultiTool".
   - Points at another backend → keep it; add a MultiTool exporter
     alongside per "Adding MultiTool alongside an existing OTel backend".
     The MultiTool exporter must use `HttpProtobuf` even if the existing one
     uses gRPC.
   - No exporter at all → add one per "Point OTel at MultiTool".
   - Uses `api-key` (lowercase) in the MultiTool exporter → that name is
     wrong; the correct header is `X-API-KEY`. Fix it via "Point OTel at
     MultiTool".

## Install OpenTelemetry from scratch

### Auto-instrumentation (recommended for most ASP.NET apps)

The OpenTelemetry .NET Automatic Instrumentation profile attaches a CLR
profiler that captures spans for ASP.NET Core, HttpClient, SqlClient, gRPC,
and more without code changes.

```powershell
# Install the auto-instrumentation tooling.
dotnet tool install --global OpenTelemetry.AutoInstrumentation.GlobalTool
```

Then run the published app under the wrapper:

```bash
otel-dotnet-auto-install        # one-time setup
otel-dotnet-auto-launch dotnet ./YourApp.dll
```

Configure via env vars (no code changes):

```bash
export CORECLR_ENABLE_PROFILING=1
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://api.multitool.run/api/otlp/v1/traces
export OTEL_EXPORTER_OTLP_HEADERS="X-API-KEY=$MULTI_API_KEY"
export OTEL_SERVICE_NAME=your-service-name
export OTEL_RESOURCE_ATTRIBUTES="service.version=$APP_VERSION,deployment.environment.name=$APP_ENVIRONMENT"
```

With auto-instrumentation in place, the "Point OTel at MultiTool" code snippets
below are optional.

### Manual SDK setup

```bash
dotnet add package OpenTelemetry
dotnet add package OpenTelemetry.Extensions.Hosting           # ASP.NET Core / .NET 6+ hosted apps
dotnet add package OpenTelemetry.Instrumentation.AspNetCore   # if ASP.NET Core
dotnet add package OpenTelemetry.Instrumentation.Http
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
```

Then add the configure block per "Point OTel at MultiTool" below.

## Point OTel at MultiTool

### Package to install

```bash
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
```

### Exporter configuration

**ASP.NET Core (Program.cs, .NET 6+):**
```csharp
using OpenTelemetry.Exporter;

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri("https://api.multitool.run/api/otlp/v1/traces");
            options.Protocol = OtlpExportProtocol.HttpProtobuf;
            options.Headers = $"X-API-KEY={Environment.GetEnvironmentVariable("MULTI_API_KEY")}";
        })
    );
```

**Important:** Set `Protocol = OtlpExportProtocol.HttpProtobuf` explicitly — the
default in some SDK versions is gRPC, and the MultiTool endpoint is HTTP-only.

### Resource with all three mandatory attributes

MultiTool requires `service.name`, `service.version`, and
`deployment.environment.name` on the Resource. `AddService` only handles the
first two; the third needs an explicit `AddAttributes`.

The *attribute names* are fixed, but the *source* of each value is the
application's choice — read from any env var the project already uses
(`GIT_SHA`, `BUILD_TAG`, `ASPNETCORE_ENVIRONMENT`, etc.) or any other
runtime source. The example below uses `APP_VERSION` and `APP_ENVIRONMENT`
as illustrative defaults; swap them for whatever the project already
exports.

```csharp
using OpenTelemetry.Resources;
using System.Collections.Generic;

builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService(
            serviceName: "your-service-name",                                            // pick a stable name
            serviceVersion: Environment.GetEnvironmentVariable("APP_VERSION"))           // or GIT_SHA, BUILD_TAG, etc.
        .AddAttributes(new Dictionary<string, object>
        {
            ["deployment.environment.name"] =
                Environment.GetEnvironmentVariable("APP_ENVIRONMENT") ?? string.Empty,  // or ASPNETCORE_ENVIRONMENT, etc.
        })
    )
    .WithTracing(tracing => tracing
        // ... instrumentation and exporter
    );
```

### Adding MultiTool alongside an existing OTel backend

If the app already calls `AddOtlpExporter(...)` pointing at another
backend, don't replace it — chain `AddOtlpExporter(...)` again with the
MultiTool config. Each call attaches an additional exporter on the same
tracing pipeline; both backends receive the same spans.

```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        // Existing exporter (kept as-is)
        .AddOtlpExporter("existing", options =>
        {
            options.Endpoint = new Uri("https://api.honeycomb.io");
            options.Protocol = OtlpExportProtocol.HttpProtobuf;
            options.Headers = $"x-honeycomb-team={Environment.GetEnvironmentVariable("HONEYCOMB_API_KEY")}";
        })
        // New MultiTool exporter
        .AddOtlpExporter("multitool", options =>
        {
            options.Endpoint = new Uri("https://api.multitool.run/api/otlp/v1/traces");
            options.Protocol = OtlpExportProtocol.HttpProtobuf;
            options.Headers = $"X-API-KEY={Environment.GetEnvironmentVariable("MULTI_API_KEY")}";
        })
    );
```

The string keys (`"existing"`, `"multitool"`) name the exporter configs so
they don't collide — required when multiple `AddOtlpExporter` calls coexist.

### .NET Framework / non-ASP.NET

```csharp
using OpenTelemetry;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .ConfigureResource(r => r
        .AddService(
            serviceName: "your-service-name",
            serviceVersion: Environment.GetEnvironmentVariable("APP_VERSION"))
        .AddAttributes(new Dictionary<string, object>
        {
            ["deployment.environment.name"] =
                Environment.GetEnvironmentVariable("APP_ENVIRONMENT") ?? string.Empty,
        }))
    .AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri("https://api.multitool.run/api/otlp/v1/traces");
        options.Protocol = OtlpExportProtocol.HttpProtobuf;
        options.Headers = $"X-API-KEY={Environment.GetEnvironmentVariable("MULTI_API_KEY")}";
    })
    .Build();
```

### `http.response.status_code` on HTTP server spans

Per OTel HTTP semconv, every HTTP server span must carry
`http.response.status_code`.

- **`OpenTelemetry.Instrumentation.AspNetCore`** sets this automatically.
  Most apps using `AddOpenTelemetry().WithTracing(t => t.AddAspNetCoreInstrumentation())`
  are already covered.
- **Manual server-span code** must set it explicitly:
  ```csharp
  Activity.Current?.SetTag("http.response.status_code", context.Response.StatusCode);
  ```

### Verify mandatory attributes when already on MultiTool

If the exporter is already pointed at MultiTool, double-check that:
- All three resource attributes (`service.name`, `service.version`,
  `deployment.environment.name`) live on the **Resource** (passed via
  `ConfigureResource(...)` / `AddService` / `AddAttributes`), not as span
  attributes set with `Activity.SetTag(...)`.
- `service.version` and `deployment.environment.name` each read from a
  runtime source (any env var, framework helper like
  `IHostEnvironment.EnvironmentName`, or assembly attribute — whatever the
  project uses), not hardcoded strings.
- Both resolved values are non-empty at runtime, and the
  `service.version` source changes every deploy.
- HTTP server spans carry `http.response.status_code`.
