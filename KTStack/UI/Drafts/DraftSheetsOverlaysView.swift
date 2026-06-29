#if DEBUG
    import KTStackKit
    import SwiftUI

    struct DraftSheetsOverlaysView: View {
        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    section("RowEditor — Edit Row") { rowEditorSheet }
                    section("DDL — New Table") { newTableSheet }
                    section("Alert — Delete row") { deleteAlert }
                    section("Alert — Destructive SQL") { destructiveAlert }
                    section("Column filter popover") { filterPopover }
                    section("Disconnected state") { disconnectedState }
                }
                .padding(24)
            }
            .background(Color(hex: 0xEDEDF0))
        }

        private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.jbMono(12, .semibold)).foregroundStyle(KTEditorTheme.label2)
                content()
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(Color(hex: 0x140F28).opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            }
        }

        private var rowEditorSheet: some View {
            sheet(title: "Edit Row", width: 440, footer: ("Cancel", "Save", .primary)) {
                fieldRow("id", type: "bigint", value: "48217", readOnly: true, isPK: true)
                fieldRow("email", type: "varchar(191)", value: "jane@example.com")
                fieldRow("name", type: "varchar(120)", value: "Jane Cooper")
                nullableFieldRow("deleted_at", type: "timestamp")
            }
        }

        private var newTableSheet: some View {
            sheet(title: "New Table", width: 520, footer: ("Cancel", "Compose SQL", .primary)) {
                fieldRow("Table name", type: nil, value: "invoices")
                columnDraft(name: "id", type: "bigint", nullable: false, primary: true)
                columnDraft(name: "amount", type: "decimal(10,2)", nullable: false, primary: false)
                columnDraft(name: "created_at", type: "timestamp", nullable: true, primary: false)
                DraftButton(title: "Add column", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private var deleteAlert: some View {
            alert(
                icon: "trash",
                iconTint: KTEditorTheme.Status.error,
                title: "Delete this row?",
                message: "This permanently removes 1 row from users. This action cannot be undone.",
                confirm: "Delete"
            )
        }

        private var destructiveAlert: some View {
            alert(
                icon: "exclamationmark.triangle.fill",
                iconTint: KTEditorTheme.Status.warning,
                title: "Run this destructive statement?",
                message: "DELETE FROM users has no WHERE clause and will affect every row.",
                confirm: "Run anyway"
            )
        }

        private var filterPopover: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Filter: balance").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(KTEditorTheme.label)
                staticInput(">= 100.00")
                HStack(spacing: 10) {
                    DraftButton(title: "Reset")
                    DraftButton(title: "Apply", kind: .primary)
                }
            }
            .padding(14)
            .frame(width: 280)
            .background(KTEditorTheme.window, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(KTEditorTheme.separator, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }

        private var disconnectedState: some View {
            VStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle").font(.system(size: 42)).foregroundStyle(KTEditorTheme.faint)
                Text("Disconnected").font(.jbMono(16)).foregroundStyle(KTEditorTheme.Status.error)
                Text("The connection to shop_dev was lost. Reconnect to continue editing.")
                    .font(.jbMono(12.5)).foregroundStyle(KTEditorTheme.label3)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
                DraftButton(title: "Reconnect", systemImage: "arrow.clockwise", kind: .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(KTEditorTheme.content, in: RoundedRectangle(cornerRadius: 10))
        }

        private func sheet(
            title: String,
            width: CGFloat,
            footer: (cancel: String, confirm: String, kind: DraftButtonKind),
            @ViewBuilder body: () -> some View
        ) -> some View {
            VStack(spacing: 0) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(KTEditorTheme.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 16)
                VStack(alignment: .leading, spacing: 12) { body() }
                    .padding(.horizontal, 18).padding(.bottom, 16)
                HStack(spacing: 10) {
                    Spacer()
                    DraftButton(title: footer.cancel)
                    DraftButton(title: footer.confirm, kind: footer.kind)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .overlay(alignment: .top) { Divider().overlay(KTEditorTheme.separator) }
            }
            .frame(width: width)
            .background(KTEditorTheme.content, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        }

        private func fieldRow(
            _ name: String,
            type: String?,
            value: String,
            readOnly: Bool = false,
            isPK: Bool = false
        ) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 12.5)).foregroundStyle(KTEditorTheme.label)
                    if isPK { Text("PK").font(.system(size: 11)).foregroundStyle(KTEditorTheme.label3) }
                    Spacer()
                    if let type { Text(type).font(.jbMono(11)).foregroundStyle(KTEditorTheme.label3) }
                }
                staticInput(value, readOnly: readOnly)
            }
        }

        private func nullableFieldRow(_ name: String, type: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 12.5)).foregroundStyle(KTEditorTheme.label)
                    Spacer()
                    Text(type).font(.jbMono(11)).foregroundStyle(KTEditorTheme.label3)
                }
                HStack(spacing: 8) {
                    staticInput("NULL", readOnly: true).opacity(0.5)
                    staticCheck("NULL", checked: true)
                }
            }
        }

        private func columnDraft(name: String, type: String, nullable: Bool, primary: Bool) -> some View {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    staticInput(name)
                    staticInput(type).frame(width: 150)
                    DraftIconButton(systemImage: "minus", tint: KTEditorTheme.Status.error)
                }
                HStack(spacing: 14) {
                    staticCheck("Nullable", checked: nullable)
                    staticCheck("Primary key", checked: primary)
                    Spacer()
                }
            }
            .padding(10)
            .background(KTEditorTheme.content2, in: RoundedRectangle(cornerRadius: 6))
        }

        private func alert(icon: String, iconTint: Color, title: String, message: String, confirm: String) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: 24)).foregroundStyle(iconTint)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(KTEditorTheme.label)
                Text(message).font(.system(size: 12.5)).foregroundStyle(KTEditorTheme.label2)
                HStack(spacing: 10) {
                    Spacer()
                    DraftButton(title: "Cancel")
                    DraftButton(title: confirm, kind: .danger)
                }
                .padding(.top, 4)
            }
            .padding(18)
            .frame(width: 360)
            .background(KTEditorTheme.content, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        }

        private func staticInput(_ value: String, readOnly: Bool = false) -> some View {
            Text(value)
                .font(.jbMono(12.5))
                .foregroundStyle(readOnly ? KTEditorTheme.label2 : KTEditorTheme.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(readOnly ? KTEditorTheme.fieldBg : KTEditorTheme.content, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(KTEditorTheme.btnBorder, lineWidth: 1))
        }

        private func staticCheck(_ label: String, checked: Bool) -> some View {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(checked ? KTEditorTheme.accent : KTEditorTheme.content)
                    .frame(width: 14, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(checked ? KTEditorTheme.accent : KTEditorTheme.btnBorder, lineWidth: 1))
                    .overlay {
                        if checked { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                    }
                Text(label).font(.system(size: 12)).foregroundStyle(KTEditorTheme.label2)
            }
        }
    }

    #if DEBUG
        #Preview {
            DraftSheetsOverlaysView().frame(width: 900, height: 760)
        }
    #endif

#endif
