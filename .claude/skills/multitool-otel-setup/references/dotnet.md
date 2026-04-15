# .NET / C# — MultiTool OTel Reference

## Package to install

```bash
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
```

## Exporter configuration

**ASP.NET Core (Program.cs, .NET 6+):**
```csharp
using OpenTelemetry.Exporter;

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri("https://api.multitool.run/otlp/v1/traces");
            options.Protocol = OtlpExportProtocol.HttpProtobuf;
            options.Headers = $"api-key={Environment.GetEnvironmentVariable("MULTI_API_KEY")}";
        })
    );
```

**Important:** Set `Protocol = OtlpExportProtocol.HttpProtobuf` explicitly — the default
in some SDK versions is gRPC, and the MultiTool endpoint is HTTP-only.

## Resource with service.version

```csharp
using OpenTelemetry.Resources;

builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService(
            serviceName: "your-service-name",       // keep existing value
            serviceVersion: Environment.GetEnvironmentVariable("APP_VERSION")
        )
    )
    .WithTracing(tracing => tracing
        // ... instrumentation and exporter
    );
```

## .NET Framework / non-ASP.NET

```csharp
using OpenTelemetry;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .ConfigureResource(r => r.AddService(
        serviceName: "your-service-name",
        serviceVersion: Environment.GetEnvironmentVariable("APP_VERSION")))
    .AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri("https://api.multitool.run/otlp/v1/traces");
        options.Protocol = OtlpExportProtocol.HttpProtobuf;
        options.Headers = $"api-key={Environment.GetEnvironmentVariable("MULTI_API_KEY")}";
    })
    .Build();
```

## Where to find the OTel setup

Search for `AddOpenTelemetry()` calls, `TracerProvider`, or `Sdk.CreateTracerProviderBuilder`.
Common locations: `Program.cs`, `Startup.cs`, or a dedicated `TelemetryExtensions.cs`.
