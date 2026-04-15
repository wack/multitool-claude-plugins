# Ruby — MultiTool OTel Reference

## Gem to install

**Gemfile:**
```ruby
gem 'opentelemetry-exporter-otlp'
```

Then run `bundle install`.

## Exporter configuration

```ruby
require 'opentelemetry/exporter/otlp'

exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(
  endpoint: 'https://api.multitool.run/otlp/v1/traces',
  headers: { 'api-key' => ENV['MULTI_API_KEY'] }
)
```

## Resource with service.version

```ruby
require 'opentelemetry/sdk'

OpenTelemetry::SDK.configure do |c|
  c.resource = OpenTelemetry::SDK::Resources::Resource.create({
    'service.name'    => 'your-service-name',      # keep existing value
    'service.version' => ENV['APP_VERSION'].to_s,
  })

  c.add_span_processor(
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
  )
end
```

If `opentelemetry-semantic_conventions` is installed, you can use the constants:
```ruby
require 'opentelemetry-semantic_conventions'

{
  OpenTelemetry::SemanticConventions::Resource::SERVICE_NAME    => 'your-service-name',
  OpenTelemetry::SemanticConventions::Resource::SERVICE_VERSION => ENV['APP_VERSION'].to_s,
}
```

## Rails

In Rails apps, OTel setup typically lives in an initializer:
`config/initializers/opentelemetry.rb`

The configure block goes at the top level of the initializer. Don't put it inside a
`Rails.application.config` block — it needs to run at load time.

## Where to find the OTel setup

Search for files calling `OpenTelemetry::SDK.configure`. Common locations:
`config/initializers/opentelemetry.rb`, `config/initializers/tracing.rb`,
`lib/telemetry.rb`, or a `tracing.rb` in the lib directory.
