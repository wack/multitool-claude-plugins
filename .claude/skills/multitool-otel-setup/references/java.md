# Java — MultiTool OTel Reference

## Dependency

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

## Exporter configuration

```java
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;

OtlpHttpSpanExporter exporter = OtlpHttpSpanExporter.builder()
    .setEndpoint("https://api.multitool.run/otlp/v1/traces")
    .addHeader("api-key", System.getenv("MULTI_API_KEY"))
    .build();
```

**Important:** Use `OtlpHttpSpanExporter` (HTTP), not `OtlpGrpcSpanExporter`. The
MultiTool endpoint is HTTP-only.

## Resource with service.version

```java
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.semconv.ServiceAttributes;

Resource resource = Resource.getDefault().merge(
    Resource.create(Attributes.of(
        ServiceAttributes.SERVICE_NAME, "your-service-name",      // keep existing value
        ServiceAttributes.SERVICE_VERSION, System.getenv("APP_VERSION")
    ))
);
```

If `ServiceAttributes` isn't available (older SDK versions), use string keys:
```java
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;

Resource resource = Resource.getDefault().merge(
    Resource.create(Attributes.of(
        AttributeKey.stringKey("service.name"), "your-service-name",
        AttributeKey.stringKey("service.version"), System.getenv("APP_VERSION")
    ))
);
```

## Wiring it together

```java
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;

SdkTracerProvider tracerProvider = SdkTracerProvider.builder()
    .addSpanProcessor(BatchSpanProcessor.builder(exporter).build())
    .setResource(resource)
    .build();
```

## Spring Boot

If using the `opentelemetry-spring-boot-starter`, configuration often goes in
`application.properties` or `application.yml`:

```properties
otel.exporter.otlp.endpoint=https://api.multitool.run
otel.exporter.otlp.traces.endpoint=https://api.multitool.run/otlp/v1/traces
otel.exporter.otlp.headers=api-key=${MULTI_API_KEY}
otel.service.name=your-service-name
otel.resource.attributes=service.version=${APP_VERSION}
```

Check whether manual SDK configuration or the Spring auto-configuration is in use —
don't mix both.

## Where to find the OTel setup

Search for `SdkTracerProvider`, `OtlpHttpSpanExporter`, or `OpenTelemetrySdkBuilder`.
In Spring Boot projects, also check for `@Configuration` classes and
`application.properties`/`application.yml`.
