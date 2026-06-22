import SwiftUI
import KTStackKit

struct KTAPIVariablesSheet: View {
    @ObservedObject var vm: APITesterViewModel
    let site: Site

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(KTColor.sep).frame(height: 0.5)
            hint
            columnHeader
            Rectangle().fill(KTColor.sep).frame(height: 0.5)
            rows
            Rectangle().fill(KTColor.sep).frame(height: 0.5)
            footer
        }
        .frame(width: 720)
        .frame(minHeight: 360, maxHeight: 620, alignment: .top)
        .background(Color.white)
        .onChange(of: vm.variables) { _ in vm.saveVariables() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            KTIconTile(tint: KTIconTint.globe, size: 30, radius: 8) {
                Image(systemName: "curlybraces").font(.system(size: 14, weight: .medium))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Variables").font(.jbMono(16, .bold)).foregroundStyle(KTColor.ink)
                Text(site.domain).font(.jbMono(12)).foregroundStyle(KTColor.muted)
            }
            Spacer()
            KTButton(title: "Done", kind: .primary) { vm.isEditingVariables = false }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(LinearGradient(colors: [Color(hex: 0xFBFBFD), .white], startPoint: .top, endPoint: .bottom))
    }

    private var hint: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(KTColor.muted)
            Text("Use {{name}} in URL, params, headers, or body. Disabled variables are skipped.")
                .font(.jbMono(12)).foregroundStyle(KTColor.faint)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Text("ON").font(.jbMono(10.5, .bold)).foregroundStyle(KTColor.ink3).frame(width: 26)
            Text("NAME").font(.jbMono(10.5, .bold)).foregroundStyle(KTColor.ink3).frame(width: 220, alignment: .leading)
            Text("VALUE").font(.jbMono(10.5, .bold)).foregroundStyle(KTColor.ink3).frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 22)
        }
        .padding(.horizontal, 18).padding(.bottom, 9)
    }

    private var rows: some View {
        VStack(spacing: 8) {
            ForEach($vm.variables) { $variable in
                row($variable)
            }
            addButton
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ variable: Binding<EditablePair>) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: variable.enabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 26)
            field(text: variable.key, placeholder: "name")
                .frame(width: 220)
            field(text: variable.value, placeholder: "value")
                .frame(maxWidth: .infinity)
            Button {
                vm.variables.removeAll { $0.id == variable.wrappedValue.id }
            } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 15)).foregroundStyle(KTColor.muted)
            }
            .buttonStyle(.plain)
            .frame(width: 22)
        }
        .opacity(variable.enabled.wrappedValue ? 1 : 0.5)
    }

    private var addButton: some View {
        Button { vm.variables.append(EditablePair(key: "", value: "")) } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus.circle.fill").font(.system(size: 14))
                Text("Add variable").font(.jbMono(13, .medium))
                Spacer()
            }
            .foregroundStyle(KTColor.accent)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KTColor.accentSoft))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("\(vm.activeVariableCount)").font(.jbMono(12, .bold)).foregroundStyle(KTColor.ink2)
            Text(vm.activeVariableCount == 1 ? "active variable" : "active variables")
                .font(.jbMono(12)).foregroundStyle(KTColor.muted)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color(hex: 0xFBFBFC))
    }

    private func field(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.jbMono(14))
            .foregroundStyle(KTColor.ink)
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0xFBFBFC)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(KTColor.fieldBorder, lineWidth: 0.5))
    }
}
