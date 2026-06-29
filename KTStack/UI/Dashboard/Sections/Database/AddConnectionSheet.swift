import KTStackKit
import SwiftUI
import UniformTypeIdentifiers

struct AddConnectionSheet: View {
    @EnvironmentObject private var store: ConnectionStore
    @Environment(\.dismiss) private var dismiss

    let editing: ConnectionProfile?

    @State private var kind: DatabaseKind = .mysql
    @State private var name = ""
    @State private var host = ""
    @State private var port = "3306"
    @State private var user = ""
    @State private var password = ""
    @State private var database = ""
    @State private var filePath = ""
    @State private var tlsMode: TLSMode = .verifyFull
    @State private var readOnly = true
    @State private var test: TestState = .idle
    @State private var importingFile = false

    private static let engines: [DatabaseKind] = [.mysql, .postgres, .sqlite, .mongodb]

    enum TestState: Equatable {
        case idle, testing, ok
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Text(editing == nil ? "Add Connection" : "Edit Connection").font(KDFont.headline)
            form
            testRow
            Divider()
            footer
        }
        .padding(KDSpacing.space4)
        .frame(width: 440)
        .onAppear(perform: hydrate)
    }

    private var form: some View {
        Form {
            Picker("Engine", selection: $kind) {
                ForEach(Self.engines, id: \.self) { Text(engineLabel($0)).tag($0) }
            }
            .disabled(editing != nil)
            .onChange(of: kind) { newKind in
                if editing == nil { port = Self.defaultPort(newKind) }
                test = .idle
            }
            if kind == .sqlite {
                sqliteFields
            } else {
                serverFields
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var sqliteFields: some View {
        TextField("Name", text: $name, prompt: Text("optional"))
        HStack {
            TextField("File", text: $filePath, prompt: Text("path to .db / .sqlite"))
            Button("Choose…") { importingFile = true }
        }
        Toggle("Read-only (open the file read-only)", isOn: $readOnly)
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.data]) { result in
                if case let .success(url) = result {
                    filePath = url.path
                    if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                    test = .idle
                }
            }
    }

    @ViewBuilder
    private var serverFields: some View {
        TextField("Name", text: $name, prompt: Text("optional"))
        TextField("Host", text: $host, prompt: Text("db.example.com"))
        TextField("Port", text: $port)
        TextField("User", text: $user)
        SecureField(
            "Password",
            text: $password,
            prompt: Text(editing == nil ? "" : "leave blank to keep current")
        )
        TextField("Database", text: $database, prompt: Text("optional"))
        Picker("TLS", selection: $tlsMode) {
            ForEach(TLSMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Toggle("Read-only (writes rejected by the server)", isOn: $readOnly)
            .onChange(of: host) { _ in test = .idle }
    }

    private var testRow: some View {
        HStack(spacing: KDSpacing.space2) {
            Button("Test Connection", action: runTest)
                .disabled(test == .testing || !isValid)
            switch test {
            case .idle: EmptyView()
            case .testing: ProgressView().controlSize(.small)
            case .ok:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(KDFont.footnote).foregroundStyle(.green)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(KDFont.footnote).foregroundStyle(.orange).lineLimit(2)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button(editing == nil ? "Add" : "Save", action: save)
                .keyboardShortcut(.defaultAction).disabled(!isValid)
        }
    }

    private var isValid: Bool {
        if kind == .sqlite {
            return !filePath.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let portValid = Int(port).map { (1...65535).contains($0) } ?? false
        let hostValid = !host.trimmingCharacters(in: .whitespaces).isEmpty
        let userValid = kind == .mongodb || !user.trimmingCharacters(in: .whitespaces).isEmpty
        return hostValid && userValid && portValid
    }

    private func engineLabel(_ kind: DatabaseKind) -> String {
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

    private func hydrate() {
        guard let e = editing else { return }
        kind = e.kind; name = e.name; host = e.host; port = String(e.port)
        user = e.user; database = e.database; filePath = e.filePath ?? ""
        tlsMode = e.tlsMode; readOnly = e.readOnly // password intentionally left blank
    }

    private func buildProfile() -> ConnectionProfile? {
        guard isValid else { return nil }
        if kind == .sqlite {
            let path = filePath.trimmingCharacters(in: .whitespaces)
            return ConnectionProfile(
                id: editing?.id ?? UUID(),
                name: name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name,
                kind: .sqlite, host: "", port: 0, user: "", database: SQLiteDriver.mainDatabase,
                filePath: path, readOnly: readOnly
            )
        }
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard let portNum = Int(port) else { return nil }
        return ConnectionProfile(
            id: editing?.id ?? UUID(),
            name: name.isEmpty ? trimmedHost : name,
            kind: kind, host: trimmedHost, port: portNum, user: user, database: database,
            tlsMode: tlsMode, readOnly: readOnly
        )
    }

    private var effectivePassword: String? {
        if !password.isEmpty { return password }
        guard let editing else { return nil }
        return try? KeychainStore().get(account: editing.id.uuidString)
    }

    private func runTest() {
        guard let profile = buildProfile() else { return }
        let pwd = effectivePassword
        test = .testing
        Task { @MainActor in
            let driver: DatabaseDriver? = profile.kind == .mongodb
                ? DocumentViewModel.defaultDriver(profile, pwd)
                : DatabaseViewModel.defaultDriver(profile, pwd)
            guard let driver else {
                test = .failed("Unsupported engine")
                return
            }
            do {
                try await driver.ping()
                test = .ok
            } catch {
                test = .failed((error as? DatabaseError)?.message ?? error.localizedDescription)
            }
        }
    }

    private func save() {
        guard let profile = buildProfile() else { return }
        let pwd = password.isEmpty ? nil : password
        if editing == nil {
            store.add(profile, password: pwd)
        } else {
            store.update(profile, password: pwd) // nil pwd keeps the existing secret
        }
        dismiss()
    }
}
