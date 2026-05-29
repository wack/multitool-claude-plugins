# Java — MultiTool OTel Reference

## Detect current state

1. **Is OTel installed at all?**
   ```bash
   grep -E 'io\.opentelemetry' pom.xml build.gradle build.gradle.kts 2>/dev/null
   ```
   Also check for an `opentelemetry-javaagent.jar` referenced from a `Dockerfile`,
   a `Procfile`, or a `JAVA_TOOL_OPTIONS=-javaagent:...` env var. No signal at
   all → "Install OpenTelemetry from scratch".

2. **Where is OTel initialized?** Search for `SdkTracerProvider`,
   `OtlpHttpSpanExporter`, or `OpenTelemetrySdkBuilder`. In Spring Boot
   projects, also look at `@Configuration` classes and `application.properties` /
   `application.yml` for `otel.*` keys. If the project uses the javaagent
   approach, configuration lives entirely in env vars / system properties —
   there's no SDK setup code.

3. **Where does the exporter point today?** Inspect `setEndpoint(...)` calls
   or the `otel.exporter.otlp.*` properties / env vars.
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

### Auto-instrumentation via the Java agent (recommended)

The OpenTelemetry Java agent attaches at JVM startup and instruments most
common libraries (servlet, JDBC, JDBC, Kafka, gRPC, etc.) with zero code
changes.

```bash
# Download the agent jar — pin to a release version in production.
curl -L -o opentelemetry-javaagent.jar \
  https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar
```

Run the app with the agent attached:

```bash
java -javaagent:./opentelemetry-javaagent.jar -jar your-app.jar
```

Configure via env vars (no code changes):

```bash
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://api.multitool.run/otlp/v1/traces
export OTEL_EXPORTER_OTLP_HEADERS="X-API-KEY=$MULTI_API_KEY"
export OTEL_SERVICE_NAME=your-service-name
export OTEL_RESOURCE_ATTRIBUTES="service.version=$APP_VERSION,deployment.environment.name=$APP_ENVIRONMENT"
```

With the agent in place, the "Point OTel at MultiTool" code snippets below are
optional — the env vars carry everything.

### Manual SDK setup

Use this when the user wants explicit control (or the project already has
some manual setup and the user prefers to keep it).

**Maven (`pom.xml`):**
```xml
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-sdk</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry.semconv</groupId>
    <artifactId>opentelemetry-semconv</artifactId>
</dependency>
```

**Gradle (Kotlin DSL):**
```kotlin
implementation("io.opentelemetry:opentelemetry-sdk")
implementation("io.opentelemetry:opentelemetry-exporter-otlp")
implementation("io.opentelemetry.semconv:opentelemetry-semconv")
```

Then follow the "Point OTel at MultiTool" code below.

## Point OTel at MultiTool

### Dependency

**Maven (`pom.xml`):**
```xml
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
```

**Gradle (`build.gradle`):**
```groovy
implementation 'io.opentelemetry:opentelemetry-exporter-otlp'
```

**Gradle Kotlin (`build.gradle.kts`):**
```kotlin
implementation("io.opentelemetry:opentelemetry-exporter-otlp")
```

### Exporter configuration

```java
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;

OtlpHttpSpanExporter exporter = OtlpHttpSpanExporter.builder()
    .setEndpoint("https://api.multitool.run/otlp/v1/traces")
    .addHeader("X-API-KEY", System.getenv("MULTI_API_KEY"))
    .build();
```

**Important:** Use `OtlpHttpSpanExporter` (HTTP), not `OtlpGrpcSpanExporter`. The
MultiTool endpoint is HTTP-only.

### Resource with all three mandatory attributes

MultiTool requires `service.name`, `service.version`, and
`deployment.environment.name` on the Resource.

The *attribute names* are fixed, but the *source* of each value is the
application's choice — read from any env var the project already uses
(`GIT_SHA`, `BUILD_TAG`, `IMAGE_TAG`, `DEPLOY_ENV`, etc.) or any other
runtime source. The example below uses `APP_VERSION` and `APP_ENVIRONMENT`
as illustrative defaults; swap them for whatever the project already
exports.

```java
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.semconv.ServiceAttributes;

Resource resource = Resource.getDefault().merge(
    Resource.create(Attributes.of(
        ServiceAttributes.SERVICE_NAME, "your-service-name",                         // pick a stable name
        ServiceAttributes.SERVICE_VERSION, System.getenv("APP_VERSION"),             // or GIT_SHA, BUILD_TAG, etc.
        AttributeKey.stringKey("deployment.environment.name"),
            System.getenv("APP_ENVIRONMENT")                                         // or DEPLOY_ENV, etc.
    ))
);
```

Use the explicit `AttributeKey.stringKey("deployment.environment.name")` —
the `DeploymentEnvironmentIncubatingAttributes` constants from older
`opentelemetry-semconv-incubating` versions use the deprecated
`deployment.environment` name (no `.name` suffix), which MultiTool will not
group correctly.

If `ServiceAttributes` isn't available (older SDK), fall back to string
keys for all three:

```java
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;

Resource resource = Resource.getDefault().merge(
    Resource.create(Attributes.of(
        AttributeKey.stringKey("service.name"), "your-service-name",
        AttributeKey.stringKey("service.version"), System.getenv("APP_VERSION"),
        AttributeKey.stringKey("deployment.environment.name"),
            System.getenv("APP_ENVIRONMENT")
    ))
);
```

### Wiring it together

```java
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;

SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
    .addSpanProcessor(BatchSpanProcessor.builder(exporter).build())
    .setResource(resource)
    .build();
```

### Adding MultiTool alongside an existing OTel backend

If the app already sends spans to another backend, don't replace that
exporter — add a second `BatchSpanProcessor` for MultiTool on the same
`SdkTracerProvider`. Each processor is an independent fan-out.

```java
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;

// Existing exporter (kept as-is)
OtlpHttpSpanExporter existingExporter = OtlpHttpSpanExporter.builder()
    .setEndpoint("https://api.honeycomb.io")
    .addHeader("x-honeycomb-team", System.getenv("HONEYCOMB_API_KEY"))
    .build();

// New MultiTool exporter
OtlpHttpSpanExporter multitoolExporter = OtlpHttpSpanExporter.builder()
    .setEndpoint("https://api.multitool.run/otlp/v1/traces")
    .addHeader("X-API-KEY", System.getenv("MULTI_API_KEY"))
    .build();

SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
    .addSpanProcessor(BatchSpanProcessor.builder(existingExporter).build())   // unchanged
    .addSpanProcessor(BatchSpanProcessor.builder(multitoolExporter).build())  // added
    .setResource(resource)
    .build();
```

If the existing setup uses the Java agent (zero-code), point the existing
config at the original backend and let the user use a custom span processor
or the agent's multi-exporter configuration (`OTEL_TRACES_EXPORTER=otlp,...`
plus per-exporter env-var sets) to fan out to MultiTool. Manual SDK code
(shown above) is the simpler path when both backends need to coexist.

### Spring Boot

If using the `opentelemetry-spring-boot-starter`, configuration often goes in
`application.properties` or `application.yml`:

```properties
otel.exporter.otlp.endpoint=https://api.multitool.run
otel.exporter.otlp.traces.endpoint=https://api.multitool.run/otlp/v1/traces
otel.exporter.otlp.headers=X-API-KEY=${MULTI_API_KEY}
otel.service.name=your-service-name
otel.resource.attributes=service.version=${APP_VERSION},deployment.environment.name=${APP_ENVIRONMENT}
```

Check whether manual SDK configuration or the Spring auto-configuration is in
use — don't mix both.

### `http.response.status_code` on HTTP server spans

Per OTel HTTP semconv, every HTTP server span must carry
`http.response.status_code`. MultiTool's HTTP error analysis depends on it.

- **Java agent + auto-instrumentation** sets this for servlet, Spring MVC,
  Spring WebFlux, and most other server frameworks automatically.
- **Manual server-span code** must set it explicitly:
  ```java
  import io.opentelemetry.semconv.HttpAttributes;

  span.setAttribute(HttpAttributes.HTTP_RESPONSE_STATUS_CODE, response.getStatus());
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
