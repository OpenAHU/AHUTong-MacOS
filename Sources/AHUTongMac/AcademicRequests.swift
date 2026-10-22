import Foundation

extension AppStore {
    /// Retry an expired session once; retain account identity across suspension.
    func performCampusRequest<Value: Sendable>(
        _ operation: (CampusCoreClient) async throws -> Value
    ) async throws -> Value {
        guard sessionPhase == .authenticated else { throw CampusClientError.sessionExpired }
        let accountID = studentID
        do {
            let result = try await operation(campusClient)
            try Task.checkCancellation()
            guard studentID == accountID, sessionPhase == .authenticated else { throw CancellationError() }
            return result
        } catch CampusClientError.sessionExpired {
            try Task.checkCancellation()
            guard studentID == accountID, sessionPhase == .authenticated else { throw CancellationError() }
            guard await attemptSilentRelogin() else { throw CampusClientError.sessionExpired }
            try Task.checkCancellation()
            guard studentID == accountID, sessionPhase == .authenticated else { throw CancellationError() }
            let result = try await operation(campusClient)
            try Task.checkCancellation()
            guard studentID == accountID, sessionPhase == .authenticated else { throw CancellationError() }
            return result
        }
    }
}
