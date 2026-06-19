import SwiftUI
import AppKit
import KDWarmKit

struct NewSiteHeader: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: KDSpacing.space3) {
            ZStack {
                RoundedRectangle(cornerRadius: KDRadius.card)
                    .fill(Color.KDStatus.info.opacity(0.12))
                Image(systemName: "plus.app.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.KDStatus.info)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("New Site").font(KDFont.title)
                Text("Create a new local development site")
                    .font(KDFont.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: KDSpacing.space2)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }
}

struct FieldIconTile: View {
    enum Symbol { case system(String), text(String) }
    let symbol: Symbol
    let tint: Color

    init(systemName: String, tint: Color = Color.KDStatus.info) {
        self.symbol = .system(systemName); self.tint = tint
    }
    init(symbolText: String, tint: Color = Color.KDStatus.info) {
        self.symbol = .text(symbolText); self.tint = tint
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(tint.opacity(0.14))
            switch symbol {
            case .system(let name):
                Image(systemName: name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            case .text(let label):
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 28, height: 22)
    }
}

struct FieldContainer<Content: View>: View {
    let focused: Bool
    let content: Content

    init(focused: Bool = false, @ViewBuilder content: () -> Content) {
        self.focused = focused
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, KDSpacing.space2)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: KDRadius.control + 2)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: KDRadius.control + 2)
                    .strokeBorder(focused ? Color.KDStatus.info : Color.secondary.opacity(0.25),
                                  lineWidth: focused ? 1.5 : 1)
            )
    }
}

struct IconTextField<Icon: View>: View {
    let icon: Icon
    let placeholder: String
    @Binding var text: String
    var font: Font = KDFont.body
    @FocusState private var focused: Bool

    init(placeholder: String,
         text: Binding<String>,
         font: Font = KDFont.body,
         @ViewBuilder icon: () -> Icon) {
        self.placeholder = placeholder
        self._text = text
        self.font = font
        self.icon = icon()
    }

    var body: some View {
        FieldContainer(focused: focused) {
            HStack(spacing: KDSpacing.space2) {
                icon
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(font)
                    .focused($focused)
            }
        }
    }
}

struct IconMenuField<Icon: View, MenuContent: View>: View {
    let icon: Icon
    let title: String
    let menu: MenuContent

    init(title: String,
         @ViewBuilder icon: () -> Icon,
         @ViewBuilder menu: () -> MenuContent) {
        self.title = title
        self.icon = icon()
        self.menu = menu()
    }

    var body: some View {
        Menu {
            menu
        } label: {
            FieldContainer {
                HStack(spacing: KDSpacing.space2) {
                    icon
                    Text(title).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

struct PasswordField: View {
    @Binding var password: String
    let onRegenerate: () -> String

    var body: some View {
        FieldContainer {
            HStack(spacing: KDSpacing.space2) {
                FieldIconTile(systemName: "lock.fill")
                TextField("", text: $password)
                    .textFieldStyle(.plain)
                    .font(KDFont.mono)
                Button { password = onRegenerate() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Regenerate")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(password, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy")
            }
        }
    }
}

struct AdvancedOptionsDisclosure<Content: View>: View {
    @Binding var expanded: Bool
    let content: Content

    init(expanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._expanded = expanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KDSpacing.space3) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: KDSpacing.space2) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Advanced Options").font(KDFont.body)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                content
            }
        }
    }
}
