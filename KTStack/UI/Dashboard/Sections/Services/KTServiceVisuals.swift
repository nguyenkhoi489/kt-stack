import KTStackKit
import SwiftUI

enum KTServiceVisuals {
    static func tint(_ kind: ServiceKind) -> KTTint {
        switch kind {
        case .nginx, .dnsmasq: KTIconTint.globe
        case .phpFpm: KTIconTint.code
        case .mysql, .postgres, .mongodb: KTIconTint.db
        case .redis: KTIconTint.cube
        case .mailpit: KTIconTint.mail
        }
    }

    static func subtitle(_ kind: ServiceKind) -> String {
        switch kind {
        case .nginx: "Reverse proxy · ports 80, 443"
        case .phpFpm: "FastCGI pools · managed with web server"
        case .dnsmasq: "*.test resolver · port 53 · privileged helper"
        case .mysql: "Database · port 3306"
        case .postgres: "Database · port 5432"
        case .redis: "Cache · port 6379"
        case .mongodb: "Document DB · port 27017"
        case .mailpit: "Mail catcher · SMTP 1025 · web 8025"
        }
    }
}
