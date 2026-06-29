import Foundation

enum MongoErrorMapper {
    static func map(_ error: any Error, isManaged: Bool, engineInstalled: Bool) -> DatabaseError {
        if let databaseError = error as? DatabaseError { return databaseError }
        if isManaged {
            return engineInstalled
                ? .engineNotRunning(kind: "MongoDB")
                : .engineNotInstalled(kind: "MongoDB")
        }
        return .connection(String(describing: error))
    }
}
