import KTStackKit
import SwiftUI
import UniformTypeIdentifiers

struct KTConnectModal: View {
    @EnvironmentObject private var store: ConnectionStore
    @EnvironmentObject private var vm: DatabaseViewModel
    @EnvironmentObject private var documentVM: DocumentViewModel
    let onClose: () -> Void
    let onConnected: (String) -> Void

    @State private var kind: DatabaseKind = .mysql
    @State private var name = ""
    @State private var host = "127.0.0.1"
    @State private var port = "3306"
    @State private var user = "root"
    @State private var password = ""
    @State private var database = ""
    @State private var filePath = ""
    @State private var tested = false
    @State private var testing = false
    @State private var testError: String?
    @State private var importingFile = false

    private static let engines: [DatabaseKind] = [.mysql, .postgres, .sqlite, .mongodb]

    var body: some View {
        KTModalCard(
            icon: "cylinder.split.1x2",
            tint: KTIconTint.code,
            title: "Connect to Database",
            subtitle: "Choose an engine and enter your connection details.",
            width: 640,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 0) {
                formBody
                footer
            }
            .onChange(of: fieldSignature) { _ in resetTest() }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.data]) { result in
                if case let .success(url) = result {
                    filePath = url.path
                    if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                    resetTest()
                }
            }
        }
    }

    private var formBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            engineGrid
            KTModalLabeledRow(label: "Connection Name") {
                KTModalField(placeholder: "optional", text: $name)
            }
            if kind == .sqlite {
                KTModalLabeledRow(label: "Database File") {
                    HStack(spacing: 8) {
                        KTModalField(placeholder: "/path/to/database.sqlite", text: $filePath, mono: true)
                        Button("Browse…") { importingFile = true }.buttonStyle(KTSecondaryButtonStyle())
                    }
                }
            } else {
                serverFields
            }
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
    }

    private var engineGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(Self.engines, id: \.self) { engine in
                KTEngineCard(
                    name: engineDisplay(engine),
                    tint: KTEngineTint.of(engine.rawValue),
                    active: kind == engine
                ) {
                    kind = engine
                    port = Self.defaultPort(engine)
                    user = Self.defaultUser(engine)
                    password = ""
                    resetTest()
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var serverFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                KTModalLabeledRow(label: "Host") { KTModalField(placeholder: "127.0.0.1", text: $host, mono: true) }
                HStack(spacing: 10) {
                    Text("Port").font(.jbMono(13.5, .regular)).foregroundStyle(KTColor.ink)
                    KTModalField(placeholder: "3306", text: $port, mono: true).frame(width: 90)
                }
            }
            KTModalLabeledRow(label: "Database") { KTModalField(placeholder: "my_app", text: $database, mono: true) }
            HStack(spacing: 14) {
                KTModalLabeledRow(label: "Username") { KTModalField(placeholder: usernamePlaceholder, text: $user, mono: true) }
                HStack(spacing: 10) {
                    Text("Password").font(.jbMono(13.5, .regular)).foregroundStyle(KTColor.ink)
                    KTModalField(placeholder: "••••••", text: $password, isSecure: true)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: runTest) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .regular))
                    Text("Test Connection").font(.jbMono(13.5, .medium))
                }
                .foregroundStyle(KTColor.ink)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(testing || !isValid)
            testStatus.padding(.leading, 12).layoutPriority(-1)
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Text("Cancel").font(.jbMono(14, .medium)).foregroundStyle(KTColor.ink)
                        .fixedSize()
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                Button(action: connect) {
                    Text("Connect").font(.jbMono(14, .regular)).foregroundStyle(.white)
                        .fixedSize()
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KTColor.accentGradient))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                .disabled(!isValid).opacity(isValid ? 1 : 0.5)
            }
            .fixedSize()
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0xF0F0F3)).frame(height: 0.5) }
    }

    @ViewBuilder
    private var testStatus: some View {
        if testing {
            ProgressView().controlSize(.small)
        } else if let error = testError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.jbMono(12.5)).foregroundStyle(KTColor.danger).lineLimit(1)
        } else if tested {
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                Text("Connection successful").font(.jbMono(13, .regular)).lineLimit(1)
            }
            .foregroundStyle(KTColor.online)
        }
    }

    private var isValid: Bool {
        if kind == .sqlite { return !filePath.trimmingCharacters(in: .whitespaces).isEmpty }
        let portValid = Int(port).map { (1...65535).contains($0) } ?? false
        let hostValid = !host.trimmingCharacters(in: .whitespaces).isEmpty
        let userValid = kind == .mongodb || !user.trimmingCharacters(in: .whitespaces).isEmpty
        return hostValid && userValid && portValid
    }

    private func buildProfile() -> ConnectionProfile? {
        guard isValid else { return nil }
        if kind == .sqlite {
            let path = filePath.trimmingCharacters(in: .whitespaces)
            return ConnectionProfile(
                name: name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name,
                kind: .sqlite,
                host: "",
                port: 0,
                user: "",
                database: SQLiteDriver.mainDatabase,
                filePath: path
            )
        }
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard let portNum = Int(port) else { return nil }
        return ConnectionProfile(
            name: name.isEmpty ? trimmedHost : name,
            kind: kind,
            host: trimmedHost,
            port: portNum,
            user: user,
            database: database
        )
    }

    private func runTest() {
        guard let profile = buildProfile() else { return }
        let pwd = password.isEmpty ? nil : password
        testing = true; testError = nil; tested = false
        Task { @MainActor in
            let driver: DatabaseDriver? = profile.kind == .mongodb
                ? DocumentViewModel.defaultDriver(profile, pwd)
                : DatabaseViewModel.defaultDriver(profile, pwd)
            guard let driver else { testing = false; testError = "Unsupported engine"; return }
            do {
                try await driver.ping()
                testing = false; tested = true
            } catch {
                testing = false
                testError = (error as? DatabaseError)?.message ?? error.localizedDescription
            }
        }
    }

    private func connect() {
        guard let profile = buildProfile() else { return }
        let pwd = password.isEmpty ? nil : password
        store.add(profile, password: pwd)
        testing = true; testError = nil; tested = false
        Task {
            if profile.kind == .mongodb {
                await documentVM.select(profile: profile)
                testing = false
                switch documentVM.connection {
                case .connected: onConnected(profile.name)
                case let .failed(error): testError = error.message
                default: testError = "Could not connect."
                }
            } else {
                await vm.select(profile: profile)
                testing = false
                switch vm.connection {
                case .connected: onConnected(profile.name)
                case let .failed(error): testError = error.message
                default: testError = "Could not connect."
                }
            }
        }
    }

    private func resetTest() {
        tested = false; testError = nil
    }

    private var fieldSignature: String {
        "\(host)|\(port)|\(user)|\(password)|\(database)|\(filePath)"
    }

    private func engineDisplay(_ kind: DatabaseKind) -> String {
        switch kind {
        case .mysql: "MySQL"
        case .postgres: "PostgreSQL"
        case .sqlite: "SQLite"
        case .mongodb: "MongoDB"
        }
    }

    private static func defaultPort(_ kind: DatabaseKind) -> String {
        switch kind {
        case .postgres: "5432"
        case .mysql: "3306"
        case .mongodb: "27017"
        case .sqlite: ""
        }
    }

    private static func defaultUser(_ kind: DatabaseKind) -> String {
        kind == .mongodb ? "" : "root"
    }

    private var usernamePlaceholder: String {
        kind == .mongodb ? "leave blank (no auth)" : "root"
    }
}

struct KTSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.jbMono(13, .medium))
            .foregroundStyle(KTColor.ink)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
