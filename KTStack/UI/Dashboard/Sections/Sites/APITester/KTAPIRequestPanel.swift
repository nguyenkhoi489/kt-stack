import KTStackKit
import SwiftUI

struct KTAPIRequestPanel: View {
    @ObservedObject var vm: APITesterViewModel
    let site: Site

    enum BuilderTab: Hashable { case params, headers, body }

    static let commonHeaders = [
        "Accept",
        "Authorization",
        "Content-Type",
        "Accept-Language",
        "Cache-Control",
        "Cookie",
        "Origin",
        "Referer",
        "User-Agent",
        "X-Requested-With",
        "X-CSRF-TOKEN",
        "X-API-Key",
    ]

    @State private var builderTab: BuilderTab = .params

    var body: some View {
        if let route = vm.selected {
            VStack(spacing: 0) {
                requestBar(route)
                settingsRow
                builderTabs
                ScrollView { tabContent(route).padding(14) }
                    .frame(maxHeight: 240)
                Rectangle().fill(KTColor.sep).frame(height: 0.5)
                responseArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "network").font(.system(size: 28)).foregroundStyle(KTColor.faint)
            Text("Select a route to start").font(.jbMono(13)).foregroundStyle(KTColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func requestBar(_: APIRoute) -> some View {
        HStack(spacing: 10) {
            methodPicker
            urlField
            KTButton(
                title: "Send",
                systemImage: "paperplane.fill",
                kind: .primary,
                isLoading: vm.isSending
            ) {
                Task { await vm.send(site: site) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sep).frame(height: 0.5) }
    }

    private var methodPicker: some View {
        let tint = KTAPIMethodStyle.tint(vm.draftMethod)
        return Menu {
            ForEach(APITesterViewModel.methods, id: \.self) { method in
                Button(method) { vm.draftMethod = method }
            }
        } label: {
            HStack(spacing: 4) {
                Text(vm.draftMethod.uppercased()).font(.jbMono(10.5, .bold)).foregroundStyle(tint.fg)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(tint.fg)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.bg))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var urlField: some View {
        HStack(spacing: 0) {
            Text("\(site.secure ? "https" : "http")://\(site.domain)")
                .font(.jbMono(12)).foregroundStyle(KTColor.faint).lineLimit(1)
            TextField("/path", text: $vm.draftPath)
                .textFieldStyle(.plain)
                .font(.jbMono(12.5))
                .foregroundStyle(KTColor.ink)
                .onChange(of: vm.draftPath) { _ in vm.syncPathParams() }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0xFBFBFC)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(KTColor.fieldBorder, lineWidth: 0.5))
        .frame(maxWidth: .infinity)
    }

    private var settingsRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                Text("Timeout").font(.jbMono(11)).foregroundStyle(KTColor.faint)
                numberField(value: timeoutBinding, suffix: "s", range: 1...300)
                    .ktTip("Seconds to wait for a response before the request times out")
            }
            HStack(spacing: 7) {
                Text("Body limit").font(.jbMono(11)).foregroundStyle(KTColor.faint)
                numberField(value: $vm.bodyDisplayLimitMB, suffix: "MB", range: 1...100)
                    .ktTip("Maximum response body size rendered in the viewer; larger bodies are truncated")
            }
            Spacer()
            if vm.hasUnresolvedPathParams {
                Label("path param empty", systemImage: "exclamationmark.triangle.fill")
                    .font(.jbMono(11)).foregroundStyle(Color(hex: 0xC07A00))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Color(hex: 0xFBFBFC))
        .overlay(alignment: .bottom) { Rectangle().fill(KTColor.sep).frame(height: 0.5) }
    }

    private var timeoutBinding: Binding<Int> {
        Binding(get: { Int(vm.timeoutSeconds) }, set: { vm.timeoutSeconds = Double($0) })
    }

    private func numberField(value: Binding<Int>, suffix: String, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 3) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.jbMono(12, .medium))
                .foregroundStyle(KTColor.ink2)
                .frame(width: 40)
                .onChange(of: value.wrappedValue) { new in
                    let clamped = min(max(new, range.lowerBound), range.upperBound)
                    if clamped != new { value.wrappedValue = clamped }
                }
            Text(suffix).font(.jbMono(11)).foregroundStyle(KTColor.faint)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(KTColor.fieldBorder, lineWidth: 0.5))
    }

    private var builderTabs: some View {
        HStack {
            KTSegmentedTabs(
                items: [
                    .init(value: BuilderTab.params, label: "Params"),
                    .init(value: .headers, label: "Headers"),
                    .init(value: .body, label: "Body"),
                ],
                selection: $builderTab
            )
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 10)
    }

    @ViewBuilder
    private func tabContent(_ route: APIRoute) -> some View {
        switch builderTab {
        case .params: paramsTab(route)
        case .headers: KTEditablePairList(
                pairs: $vm.requestDraft.headers,
                keyPlaceholder: "Header",
                valuePlaceholder: "Value",
                keySuggestions: Self.commonHeaders,
                variableNames: vm.variableNames
            )
        case .body: bodyTab(route)
        }
    }

    private func paramsTab(_ route: APIRoute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !vm.requestDraft.pathParams.isEmpty {
                sectionLabel("PATH")
                KTEditablePairList(
                    pairs: $vm.requestDraft.pathParams,
                    keyPlaceholder: "Name",
                    valuePlaceholder: "Value",
                    lockKeys: true,
                    variableNames: vm.variableNames
                )
            }
            sectionLabel("QUERY")
            KTEditablePairList(
                pairs: $vm.requestDraft.query,
                keyPlaceholder: "Key",
                valuePlaceholder: "Value",
                variableNames: vm.variableNames
            )
            fieldsReference(route)
        }
    }

    private func bodyTab(_ route: APIRoute) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            KTSegmentedTabs(
                items: RequestBodyMode.allCases.map { .init(value: $0, label: $0.label) },
                selection: $vm.requestDraft.bodyMode
            )
            Group {
                switch vm.requestDraft.bodyMode {
                case .none:
                    Text("No request body").font(.jbMono(11.5)).foregroundStyle(KTColor.faint)
                case .json:
                    TextEditor(text: $vm.requestDraft.bodyText)
                        .font(.jbMono(12))
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(hex: 0xFBFBFC)))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(KTColor.fieldBorder, lineWidth: 0.5))
                case .form:
                    KTEditablePairList(
                        pairs: $vm.requestDraft.formFields,
                        keyPlaceholder: "Key",
                        valuePlaceholder: "Value",
                        variableNames: vm.variableNames
                    )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            fieldsReference(route)
        }
    }

    @ViewBuilder
    private func fieldsReference(_ route: APIRoute) -> some View {
        if !route.rulesResolved {
            HStack(spacing: 7) {
                Image(systemName: "info.circle").font(.system(size: 12))
                Text("Validation rules unavailable for this route.").font(.jbMono(11.5))
            }
            .foregroundStyle(Color(hex: 0xC07A00))
            .padding(.top, 4)
        } else if !route.fields.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("RULES")
                ForEach(route.fields, id: \.name) { field in
                    HStack(alignment: .top, spacing: 8) {
                        Text(field.name).font(.jbMono(12, .medium)).foregroundStyle(KTColor.ink2)
                        if field.required {
                            Text("required").font(.jbMono(10, .bold)).foregroundStyle(KTColor.danger)
                        }
                        Spacer(minLength: 8)
                        Text(field.rules.joined(separator: " · "))
                            .font(.jbMono(11)).foregroundStyle(KTColor.faint)
                            .frame(maxWidth: 220, alignment: .trailing)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.jbMono(11, .bold)).foregroundStyle(KTColor.ink3)
    }

    @ViewBuilder
    private var responseArea: some View {
        if let error = vm.sendError {
            banner(error, color: KTColor.danger, icon: "xmark.octagon.fill")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let response = vm.response {
            KTAPIResponseView(response: response, bodyLimitKB: vm.bodyDisplayLimitMB * 1024)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle").font(.system(size: 22)).foregroundStyle(KTColor.faint)
                Text("Send the request to see the response").font(.jbMono(12)).foregroundStyle(KTColor.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func banner(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 13))
            Text(text).font(.jbMono(12)).foregroundStyle(KTColor.ink2)
            Spacer()
        }
        .foregroundStyle(color)
        .padding(14)
    }
}

struct KTEditablePairList: View {
    @Binding var pairs: [EditablePair]
    var keyPlaceholder: String
    var valuePlaceholder: String
    var lockKeys: Bool = false
    var keySuggestions: [String] = []
    var variableNames: [String] = []

    var body: some View {
        VStack(spacing: 6) {
            ForEach($pairs) { $pair in
                HStack(spacing: 8) {
                    fieldBox(disabled: lockKeys) {
                        field(text: $pair.key, placeholder: keyPlaceholder, disabled: lockKeys)
                        if !lockKeys, !keySuggestions.isEmpty {
                            pickerMenu(icon: "chevron.down", items: keySuggestions) { pair.key = $0 }
                        }
                    }
                    .frame(width: 170)
                    fieldBox(disabled: false) {
                        if variableNames.isEmpty {
                            field(text: $pair.value, placeholder: valuePlaceholder, disabled: false)
                        } else {
                            KTVariableTextField(
                                text: $pair.value,
                                placeholder: valuePlaceholder,
                                variableNames: variableNames
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    if !lockKeys {
                        Button { pairs.removeAll { $0.id == pair.id } } label: {
                            Image(systemName: "minus.circle").font(.system(size: 13)).foregroundStyle(KTColor.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !lockKeys {
                Button { pairs.append(EditablePair(key: "", value: "")) } label: {
                    Label("Add", systemImage: "plus").font(.jbMono(11.5)).foregroundStyle(KTColor.accent)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func fieldBox(disabled _: Bool, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 4) { content() }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: 0xFBFBFC)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(KTColor.fieldBorder, lineWidth: 0.5))
    }

    private func field(text: Binding<String>, placeholder: String, disabled: Bool) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.jbMono(12))
            .foregroundStyle(disabled ? KTColor.ink3 : KTColor.ink)
            .disabled(disabled)
    }

    private func pickerMenu(icon: String, items: [String], onPick: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(items, id: \.self) { item in
                Button(item) { onPick(item) }
            }
        } label: {
            Image(systemName: icon).font(.system(size: 10, weight: .medium)).foregroundStyle(KTColor.muted)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
