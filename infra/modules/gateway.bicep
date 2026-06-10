param location string
param suffix string
param tags object
param envId string
param acrServer string
param acrName string
@secure()
param acrPassword string
param aiConnStr string
param orderServiceUrl string
param paymentServiceUrl string
param dtEnvVars array = []
param dtSecrets array = []

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'gateway-${suffix}'
  location: location
  tags: union(tags, { 'azd-service-name': 'gateway' })
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: envId
    configuration: {
      secrets: concat([
        { name: 'acr-password', value: acrPassword }
      ], dtSecrets)
      registries: [
        { server: acrServer, username: acrName, passwordSecretRef: 'acr-password' }
      ]
      ingress: { external: true, targetPort: 8080 }
    }
    template: {
      containers: [
        {
          name: 'gateway'
          image: 'mcr.microsoft.com/dotnet/samples:aspnetapp'
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: concat([
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aiConnStr }
            { name: 'ORDER_SERVICE_URL', value: orderServiceUrl }
            { name: 'PAYMENT_SERVICE_URL', value: paymentServiceUrl }
          ], dtEnvVars)
        }
      ]
      scale: {
        minReplicas: 2
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '15'
              }
            }
          }
        ]
      }
    }
  }
}

// ── Action Group for gateway alerts ──

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'sre-workshop-ag'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'sre-ag'
    enabled: true
  }
}

// ── Gateway Latency Alert (ResponseTime P95 > 2000ms) ──

resource latencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'High-Latency-Gateway'
  location: 'global'
  tags: tags
  properties: {
    description: 'Gateway latency exceeded SLO — P95 response time above 2 seconds'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    autoMitigate: true
    scopes: [
      app.id
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'high-p95-latency'
          metricName: 'ResponseTime'
          metricNamespace: 'Microsoft.App/containerApps'
          operator: 'GreaterThan'
          threshold: 2000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

output url string = 'https://${app.properties.configuration.ingress.fqdn}'
