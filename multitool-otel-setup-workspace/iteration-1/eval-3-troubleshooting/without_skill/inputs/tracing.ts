import { NodeSDK } from '@opentelemetry/sdk-node'
import { resourceFromAttributes } from '@opentelemetry/resources'
import { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } from '@opentelemetry/semantic-conventions'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'

const traceExporter = new OTLPTraceExporter({
  url: 'https://api.multitool.run/otlp/v1/traces',
  headers: {
    'api-key': process.env['MULTI_API_KEY'] ?? '',
  },
})

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'user-service',
    [ATTR_SERVICE_VERSION]: process.env['APP_VERSION'] ?? 'unknown',
  }),
  traceExporter,
})

sdk.start()
