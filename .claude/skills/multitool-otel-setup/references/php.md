# PHP — MultiTool OTel Reference

## Package to install

```bash
composer require open-telemetry/exporter-otlp
composer require open-telemetry/sdk
```

## Exporter configuration

```php
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;

$transport = (new OtlpHttpTransportFactory())->create(
    'https://api.multitool.run/otlp/v1/traces',
    'application/x-protobuf',
    ['api-key' => getenv('MULTI_API_KEY')]
);

$exporter = new SpanExporter($transport);
```

**Important:** Use the HTTP exporter (`OtlpHttpTransportFactory`), not the gRPC variant.
The MultiTool endpoint is HTTP-only.

## Resource with service.version

```php
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\API\Common\Attribute\Attributes;
use OpenTelemetry\SemConv\ResourceAttributes;

$resource = ResourceInfo::create(
    Attributes::create([
        ResourceAttributes::SERVICE_NAME    => 'your-service-name',    // keep existing value
        ResourceAttributes::SERVICE_VERSION => getenv('APP_VERSION') ?: '',
    ])
);
```

## Wiring it together

```php
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;
use OpenTelemetry\API\Globals;

$tracerProvider = TracerProvider::builder()
    ->addSpanProcessor(BatchSpanProcessor::builder($exporter)->build())
    ->setResource($resource)
    ->build();

Globals::registerInitializer(function (Configurator $configurator) use ($tracerProvider) {
    return $configurator->withTracerProvider($tracerProvider);
});
```

## Laravel

In Laravel, OTel setup usually goes in a service provider:

```php
// app/Providers/TelemetryServiceProvider.php
public function boot(): void
{
    // setup code here
}
```

Register it in `config/app.php` under `providers`.

## Environment variable approach

The OTel PHP SDK also supports configuration via environment variables, which can be
simpler if the existing setup already uses them:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://api.multitool.run
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://api.multitool.run/otlp/v1/traces
OTEL_EXPORTER_OTLP_HEADERS=api-key=your-key
OTEL_SERVICE_VERSION=${APP_VERSION}
```

## Where to find the OTel setup

Search for files importing `OpenTelemetry\SDK\Trace\TracerProvider` or
`OpenTelemetry\API\Globals`. Common locations: service providers, bootstrap files, or
dedicated `telemetry.php` / `tracing.php` files.
