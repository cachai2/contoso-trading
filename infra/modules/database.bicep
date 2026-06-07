param location string
param suffix string
param tags object
param peSubnetId string = ''
param vnetId string = ''

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: 'pg-${suffix}'
  location: location
  tags: tags
  sku: { name: 'Standard_B1ms'
    tier: 'Burstable' }
  properties: {
    version: '15'
    administratorLogin: 'appadmin'
    administratorLoginPassword: 'Tr@ding${uniqueString(suffix)}!'
    storage: { storageSizeGB: 32 }
    network: {
      publicNetworkAccess: !empty(peSubnetId) ? 'Disabled' : 'Enabled'
    }
  }
}

resource db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: server
  name: 'tradingdb'
}

resource fw 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = if (empty(peSubnetId)) {
  parent: server
  name: 'AllowAzure'
  properties: { startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0' }
}

// ── Private Endpoint for PostgreSQL ──

resource peDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = if (!empty(peSubnetId)) {
  name: 'privatelink.postgres.database.azure.com'
  location: 'global'
  tags: tags
}

resource peDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (!empty(peSubnetId)) {
  parent: peDnsZone
  name: 'pg-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource pgPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = if (!empty(peSubnetId)) {
  name: 'pe-pg-${suffix}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pg-connection'
        properties: {
          privateLinkServiceId: server.id
          groupIds: [ 'postgresqlServer' ]
        }
      }
    ]
  }
}

resource peDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = if (!empty(peSubnetId)) {
  parent: pgPrivateEndpoint
  name: 'pg-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-postgres'
        properties: {
          privateDnsZoneId: peDnsZone.id
        }
      }
    ]
  }
}

output connStr string = 'Host=${server.properties.fullyQualifiedDomainName};Database=tradingdb;Username=appadmin;Password=Tr@ding${uniqueString(suffix)}!;Ssl Mode=Require;Trust Server Certificate=true'
output serverName string = server.name
output serverFqdn string = server.properties.fullyQualifiedDomainName
