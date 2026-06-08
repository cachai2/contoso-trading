param location string
param suffix string
param tags object
param envId string
param acrServer string
param acrName string
@secure()
param acrPassword string
param aiConnStr string
param dbConnStr string
param dtEnvVars array = []
param dtSecrets array = []

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'payment-svc-${suffix}'
  location: location
  tags: union(tags, { 'azd-service-name': 'payment-service' })
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: envId
    configuration: {
      secrets: concat([
        { name: 'acr-password', value: acrPassword }
        { name: 'db-conn', value: dbConnStr }
      ], dtSecrets)
      registries: [
        { server: acrServer, username: acrName, passwordSecretRef: 'acr-password' }
      ]
      ingress: { external: false, targetPort: 8080 }
    }
    template: {
      containers: [
        {
          name: 'payment-service'
          image: 'mcr.microsoft.com/dotnet/samples:aspnetapp'
          resources: { cpu: json('0.5'), memory: '1Gi' }
          env: concat([
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: aiConnStr }
            // CRITICAL: DATABASE_URL MUST use secretRef to db-conn.
            // If this is removed or overridden to plaintext, payment-svc enters
            // silent mock mode — bookings appear to succeed but are NOT persisted.
            // See INC0010009 (2026-06-08) for the incident caused by this.
            { name: 'DATABASE_URL', secretRef: 'db-conn' }
            { name: 'POOL_LIMIT', value: '10' }
          ], dtEnvVars)
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

output url string = 'https://${app.properties.configuration.ingress.fqdn}'
