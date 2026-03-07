import Foundation

final class DependencyContainer {
    let credentialsStore: CredentialsStore
    let cloudClient: CloudClient
    let deviceRepository: DeviceRepository
    let deviceController: DeviceController

    init(credentialsStore: CredentialsStore = CredentialsStore()) {
        self.credentialsStore = credentialsStore

        let client = CloudClient(apiKeyProvider: { credentialsStore.loadAPIKey() })
        let lanDiscovery = LanDiscoveryService()
        let lanControl = LanControlService()

        self.cloudClient = client
        self.deviceRepository = HybridDeviceRepository(cloudClient: client, lanDiscovery: lanDiscovery)
        self.deviceController = CommandRouter(
            lanTransport: LanTransport(service: lanControl),
            cloudTransport: CloudTransport(client: client)
        )
    }
}
