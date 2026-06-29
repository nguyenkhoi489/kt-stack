import KTStackKit
import SwiftUI

struct KTNewDatabaseModal: View {
    @EnvironmentObject private var vm: DatabaseViewModel
    let onClose: () -> Void
    let onCreated: (String) -> Void

    @State private var name = ""
    @State private var submitting = false

    private var engineKind: DatabaseKind {
        vm.selectedProfile?.kind ?? .mysql
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !submitting
    }

    var body: some View {
        KTModalCard(
            icon: "cylinder.split.1x2",
            tint: KTIconTint.db,
            title: "New Database",
            subtitle: "Create an empty database on this server.",
            width: 460,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 0) {
                fields
                footer
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("Database name")
            KTModalField(placeholder: "my_database", text: $name, mono: true)
            fieldLabel("Engine").padding(.top, 16)
            KTEngineCard(
                name: engineDisplay(engineKind),
                tint: KTEngineTint.of(engineKind.rawValue),
                active: true,
                action: {}
            )
            .allowsHitTesting(false)
            .padding(.top, 2)
        }
        .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.jbMono(12.5, .regular)).foregroundStyle(KTColor.ink2)
            .padding(.bottom, 7)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button(action: onClose) {
                Text("Cancel").font(.jbMono(14, .medium)).foregroundStyle(KTColor.ink)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(KTColor.btnBorder, lineWidth: 0.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            Button(action: create) {
                Text(submitting ? "Creating…" : "Create")
                    .font(.jbMono(14, .regular)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KTColor.accentGradient))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0xF0F0F3)).frame(height: 0.5) }
    }

    private func create() {
        guard canSubmit else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        submitting = true
        Task {
            let created = await vm.createDatabase(named: trimmed)
            submitting = false
            if created { onCreated(trimmed) }
        }
    }

    private func engineDisplay(_ kind: DatabaseKind) -> String {
        switch kind {
        case .mysql: "MySQL"
        case .postgres: "PostgreSQL"
        case .sqlite: "SQLite"
        case .mongodb: "MongoDB"
        }
    }
}
