import AppKit
import Combine
import Foundation

/// MainActor manager owning the FSearch socket connection, search dispatching, and debouncing.
@MainActor
public final class FileSearchManager: ObservableObject {
    @Published public private(set) var results: [FileSearchItem] = []
    @Published public private(set) var isConnected = false
    @Published public private(set) var isSearching = false
    @Published public private(set) var tookMicros: UInt64 = 0
    @Published public private(set) var daemonStatus: FSearchStatus?
    @Published public private(set) var errorMessage: String?

    private let client: FSearchClient
    private var activeTask: Task<Void, Never>?
    private var currentQuery: String = ""

    public init(client: FSearchClient = FSearchClient()) {
        self.client = client
    }

    public func start() {
        Task { [weak self] in
            await self?.checkConnection()
        }
    }

    public func checkConnection() async {
        let running = await client.ensureDaemonRunning()
        isConnected = running
        if running {
            do {
                let status = try await client.status()
                daemonStatus = status
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            daemonStatus = nil
            errorMessage = "FSearch daemon not running"
        }
    }

    /// Submits a query to the fsearch daemon with cancellation of superseded searches.
    public func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed != currentQuery else { return }
        currentQuery = trimmed

        activeTask?.cancel()

        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            tookMicros = 0
            errorMessage = nil
            return
        }

        isSearching = true

        activeTask = Task { [weak self, client] in
            guard let self else { return }

            // Minimal typing debounce
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
            if Task.isCancelled { return }

            do {
                let (items, micros) = try await client.search(query: trimmed, limit: 50)
                if Task.isCancelled { return }

                self.results = items
                self.tookMicros = micros
                self.isConnected = true
                self.isSearching = false
                self.errorMessage = nil
            } catch {
                if Task.isCancelled { return }
                self.isSearching = false
                self.errorMessage = error.localizedDescription
                // If socket dropped, attempt reconnect on next query
                if !self.isConnected {
                    self.results = []
                }
            }
        }
    }

    public func clear() {
        activeTask?.cancel()
        currentQuery = ""
        results = []
        isSearching = false
        tookMicros = 0
    }
}
