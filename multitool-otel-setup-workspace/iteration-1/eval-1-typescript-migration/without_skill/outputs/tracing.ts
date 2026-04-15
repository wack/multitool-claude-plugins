import { NodeSDK } from '@opentelemetry/sdk-node'
import { resourceFromAttributes } from '@opentelemetry/resources'
import {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
} from '@opentelemetry/semantic-conventions'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'

const traceExporter = new OTLPTraceExporter({
  url: 'https://ingest.multitool.run/v1/traces',
  headers: {
    'x-api-key': process.env.MULTITOOL_API_KEY ?? '',
  },
})

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'my-api',
    [ATTR_SERVICE_VERSION]: process.env.GIT_SHA ?? 'unknown',
  }),
  traceExporter,
})

sdk.start()
