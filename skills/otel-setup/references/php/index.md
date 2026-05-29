# PHP — MultiTool OTel Reference

## Detect current state

1. **Is OTel installed at all?**
   ```bash
   jq -r '.require // {}, ."require-dev" // {}' composer.json 2>/dev/null \
     | grep -E '"open-telemetry/' | head
   ```
   Also check `php -m 2>/dev/null | grep -i opentelemetry` for the PHP extension.
   No matches anywhere → "Install OpenTelemetry from scratch".

2. **Where is OTel initialized?** Search for files importing
   `OpenTelemetry\SDK\Trace\TracerProvider` or `OpenTelemetry\API\Globals`.
   Common locations: service providers, bootstrap files, or dedicated
   `telemetry.php` / `tracing.php` files. Laravel: look in `app/Providers/`.
   Symfony: look in `config/services.yaml` and `config/packages/`.

3. **Where does the exporter point today?** Inspect the
   `OtlpHttpTransportFactory->create(...)` URL or the `OTEL_EXPORTER_OTLP_*`
   env vars.
   - `https://api.multitool.run/otlp/v1/traces` with `X-API-KEY` header from
     `MULTI_API_KEY` → already on MultiTool; jump to "Verify mandatory
     attributes when already on MultiTool".
   - Points at another backend → keep it; add a MultiTool exporter
     alongside per "Adding MultiTool alongside an existing OTel backend".
   - No exporter at all → add one per "Point OTel at MultiTool".
   - Uses `api-key` (lowercase) in the MultiTool exporter → that name is
     wrong; the correct header is `X-API-KEY`. Fix it via "Point OTel at
     MultiTool".

## Install OpenTelemetry from scratch

### Auto-instrumentation (recommended where the OTel PHP extension is available)

Auto-instrumentation requires the `opentelemetry` PHP extension (installed via
PECL) plus per-library auto-instrumentation packages.

```bash
# Install the OTel PHP extension via PECL (requires php-dev / php-pear).
pecl install opentelemetry

# Then add it to php.ini:
#   extension=opentelemetry

# Auto-instrumentation packages for whichever libraries the app uses:
composer require \
  open-telemetry/sdk \
  open-telemetry/exporter-otlp \
  open-telemetry/opentelemetry-auto-laravel       # if Laravel
composer require open-telemetry/opentelemetry-auto-symfony      # if Symfony
composer require open-telemetry/opentelemetry-auto-slim         # if Slim
composer require open-telemetry/opentelemetry-auto-psr18        # for PSR-18 HTTP clients
```

With the extension loaded, the auto-instrumentation packages hook in without
code changes. Configure via env vars (no SDK setup code needed):

```bash
export OTEL_PHP_AUTOLOAD_ENABLED=true
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://api.multitool.run/otlp/v1/traces
export OTEL_EXPORTER_OTLP_HEADERS="X-API-KEY=$MULTI_API_KEY"
export OTEL_SERVICE_NAME=your-service-name
export OTEL_RESOURCE_ATTRIBUTES="service.version=$APP_VERSION,deployment.environment.name=$APP_ENVIRONMENT"
```

If the host can't install the PHP extension (shared hosting, locked-down PaaS),
fall through to manual SDK setup.

### Manual SDK setup

```bash
composer require open-telemetry/sdk open-telemetry/exporter-otlp
```

Then bootstrap as shown in "Point OTel at MultiTool" below.

## Point OTel at MultiTool

### Package to install

```bash
composer require open-telemetry/exporter-otlp
composer require open-telemetry/sdk
```

### Exporter configuration

```php
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;

$transport = (new OtlpHttpTransportFactory())->create(
    'https://api.multitool.run/otlp/v1/traces',
    'application/x-protobuf',
    ['X-API-KEY' => getenv('MULTI_API_KEY')]
);

$exporter = new SpanExporter($transport);
```

**Important:** Use the HTTP exporter (`OtlpHttpTransportFactory`), not the gRPC
variant. The MultiTool endpoint is HTTP-only.

### Resource with all three mandatory attributes

MultiTool requires `service.name`, `service.version`, and
`deployment.environment.name` on the Resource.

The *attribute names* are fixed, but the *source* of each value is the
application's choice — read from any env var the project already uses
(`GIT_SHA`, `BUILD_TAG`, `APP_ENV`, etc.) or any other runtime source. The
example below uses `APP_VERSION` and `APP_ENVIRONMENT` as illustrative
defaults; swap them for whatever the project already exports.

```php
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\API\Common\Attribute\Attributes;
use OpenTelemetry\SemConv\ResourceAttributes;

$resource = ResourceInfo::create(
    Attributes::create([
        ResourceAttributes::SERVICE_NAME      => 'your-service-name',           // pick a stable name
        ResourceAttributes::SERVICE_VERSION   => getenv('APP_VERSION') ?: '',   // or GIT_SHA, BUILD_TAG, etc.
        'deployment.environment.name'         => getenv('APP_ENVIRONMENT') ?: '', // or APP_ENV, etc.
    ])
);
```

`ResourceAttributes::DEPLOYMENT_ENVIRONMENT` (if your `open-telemetry/sem-conv`
version exports it) uses the deprecated `deployment.environment` name —
prefer the string literal `'deployment.environment.name'` so MultiTool can
read it.

### Wiring it together

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

### Adding MultiTool alongside an existing OTel backend

If the app already builds a `TracerProvider` with an existing span
processor, don't replace it — chain `->addSpanProcessor(...)` again with a
MultiTool exporter. Each processor is an independent fan-out.

```php
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SDK\Trace\SpanProcessor\BatchSpanProcessor;

// Existing exporter (kept as-is)
$existingExporter = build_existing_exporter();

// New MultiTool exporter
$multitoolTransport = (new OtlpHttpTransportFactory())->create(
    'https://api.multitool.run/otlp/v1/traces',
    'application/x-protobuf',
    ['X-API-KEY' => getenv('MULTI_API_KEY')]
);
$multitoolExporter = new SpanExporter($multitoolTransport);

$tracerProvider = TracerProvider::builder()
    ->addSpanProcessor(BatchSpanProcessor::builder($existingExporter)->build())    // unchanged
    ->addSpanProcessor(BatchSpanProcessor::builder($multitoolExporter)->build())   // added
    ->setResource($resource)
    ->build();
```

### Laravel

In Laravel, OTel setup usually goes in a service provider:

```php
// app/Providers/TelemetryServiceProvider.php
public function boot(): void
{
    // setup code here
}
```

Register it in `config/app.php` under `providers`.

### Environment variable approach

The OTel PHP SDK also supports configuration via environment variables, which
can be simpler if the existing setup already uses them:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://api.multitool.run
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://api.multitool.run/otlp/v1/traces
OTEL_EXPORTER_OTLP_HEADERS=X-API-KEY=your-key
OTEL_SERVICE_VERSION=${APP_VERSION}
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=${APP_ENVIRONMENT}
```

### `http.response.status_code` on HTTP server spans

Per OTel HTTP semconv, every HTTP server span must carry
`http.response.status_code`.

- **`opentelemetry-auto-laravel`, `-symfony`, `-slim`** set this automatically.
- **Manual server-span code** must set it explicitly:
  ```php
  $span->setAttribute('http.response.status_code', $response->getStatusCode());
  ```

### Verify mandatory attributes when already on MultiTool

If the exporter is already pointed at MultiTool, double-check that:
- All three resource attributes (`service.name`, `service.version`,
  `deployment.environment.name`) live on the **Resource** (passed via
  `setResource(...)`), not as span attributes.
- `service.version` and `deployment.environment.name` each read from a
  runtime source (any env var or framework helper — whatever the project
  uses), not hardcoded strings.
- Both resolved values are non-empty at runtime, and the
  `service.version` source changes every deploy.
- HTTP server spans carry `http.response.status_code`.
