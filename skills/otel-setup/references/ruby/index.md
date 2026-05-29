# Ruby — MultiTool OTel Reference

## Detect current state

1. **Is OTel installed at all?**
   ```bash
   grep -E '^\s*gem\s+["'\'']opentelemetry' Gemfile Gemfile.lock 2>/dev/null
   ```
   No matches → "Install OpenTelemetry from scratch".

2. **Where is OTel initialized?** Search for files calling
   `OpenTelemetry::SDK.configure`. Common locations:
   `config/initializers/opentelemetry.rb`, `config/initializers/tracing.rb`,
   `lib/telemetry.rb`, or a `tracing.rb` in `lib/`.

3. **Where does the exporter point today?** Inspect the
   `OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: ...)` call.
   - `https://api.multitool.run/api/otlp/v1/traces` with `X-API-KEY` header from
     `MULTI_API_KEY` → already on MultiTool; jump to "Verify mandatory
     attributes when already on MultiTool".
   - Points at another backend → keep it; add a MultiTool exporter
     alongside per "Adding MultiTool alongside an existing OTel backend".
   - No exporter at all → add one per "Point OTel at MultiTool".
   - Uses `api-key` (lowercase) in the MultiTool exporter → that name is
     wrong; the correct header is `X-API-KEY`. Fix it via "Point OTel at
     MultiTool".

## Install OpenTelemetry from scratch

### Auto-instrumentation (recommended for Rails / Rack apps)

The `opentelemetry-instrumentation-all` meta-gem pulls in instrumentations
for ActiveRecord, Rack, Sinatra, Net::HTTP, Redis, and most other libraries
the user's app likely touches.

**Gemfile:**
```ruby
gem 'opentelemetry-sdk'
gem 'opentelemetry-exporter-otlp'
gem 'opentelemetry-instrumentation-all'
```

Then `bundle install` and create `config/initializers/opentelemetry.rb` (Rails)
or a `tracing.rb` required at boot (non-Rails). The body of that file is what
"Point OTel at MultiTool" describes — plus a `c.use_all` call to turn on every
discovered instrumentation:

```ruby
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry/instrumentation/all'

OpenTelemetry::SDK.configure do |c|
  c.use_all
  # ... exporter + resource (see below)
end
```

### Manual / explicit SDK setup

Skip `opentelemetry-instrumentation-all` and pick individual instrumentation
gems (e.g. `opentelemetry-instrumentation-rails`,
`opentelemetry-instrumentation-net_http`) if the user wants tighter control.
The configure block looks the same minus `c.use_all`.

## Point OTel at MultiTool

### Gem to install

**Gemfile:**
```ruby
gem 'opentelemetry-exporter-otlp'
```

Then run `bundle install`.

### Exporter configuration

```ruby
require 'opentelemetry/exporter/otlp'

exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(
  endpoint: 'https://api.multitool.run/api/otlp/v1/traces',
  headers: { 'X-API-KEY' => ENV['MULTI_API_KEY'] }
)
```

### Resource with all three mandatory attributes

MultiTool requires `service.name`, `service.version`, and
`deployment.environment.name` on the Resource.

The *attribute names* are fixed, but the *source* of each value is the
application's choice — read from any env var the project already uses
(`GIT_SHA`, `BUILD_TAG`, `RAILS_ENV`, etc.) or any other runtime source.
The example below uses `APP_VERSION` and `APP_ENVIRONMENT` as illustrative
defaults; swap them for whatever the project already exports.

```ruby
require 'opentelemetry/sdk'

OpenTelemetry::SDK.configure do |c|
  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
    'service.name'                => 'your-service-name',           # pick a stable name
    'service.version'             => ENV['APP_VERSION'].to_s,       # or GIT_SHA, BUILD_TAG, etc.
    'deployment.environment.name' => ENV['APP_ENVIRONMENT'].to_s,   # or RAILS_ENV, DEPLOY_ENV, etc.
  })

  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
  )
end
```

`opentelemetry-semantic_conventions` does ship `SERVICE_NAME` and
`SERVICE_VERSION` constants, but the deployment-environment constant uses
the old name (`deployment.environment`). Use the string literal
`deployment.environment.name` to match what MultiTool expects.

### Adding MultiTool alongside an existing OTel backend

If the configure block already attaches a span processor pointing at
another backend, don't replace it — `add_span_processor` is additive, so
just call it again with a new exporter pointing at MultiTool. Each
processor is an independent fan-out.

```ruby
require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'

OpenTelemetry::SDK.configure do |c|
  c.resource = resource  # whatever you built above

  # Existing exporter (kept as-is)
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: 'https://api.honeycomb.io',
        headers: { 'x-honeycomb-team' => ENV['HONEYCOMB_API_KEY'] }
      )
    )
  )

  # New MultiTool exporter
  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: 'https://api.multitool.run/api/otlp/v1/traces',
        headers: { 'X-API-KEY' => ENV['MULTI_API_KEY'] }
      )
    )
  )
end
```

### Rails

In Rails apps, OTel setup typically lives in an initializer:
`config/initializers/opentelemetry.rb`.

The configure block goes at the top level of the initializer. Don't put it
inside a `Rails.application.config` block — it needs to run at load time.

### `http.response.status_code` on HTTP server spans

Per OTel HTTP semconv, every HTTP server span must carry
`http.response.status_code`.

- **`opentelemetry-instrumentation-rack`, `-rails`, `-sinatra`** set this
  automatically.
- **Manual server-span code** must set it explicitly:
  ```ruby
  span.set_attribute('http.response.status_code', response.status)
  ```

### Verify mandatory attributes when already on MultiTool

If the exporter is already pointed at MultiTool, double-check that:
- All three resource attributes (`service.name`, `service.version`,
  `deployment.environment.name`) live on the **Resource** (passed via
  `c.resource = ...`), not as span attributes.
- `service.version` and `deployment.environment.name` each read from a
  runtime source (any env var or framework helper like `Rails.env` —
  whatever the project uses), not hardcoded strings.
- Both resolved values are non-empty at runtime, and the
  `service.version` source changes every deploy.
- HTTP server spans carry `http.response.status_code`.
