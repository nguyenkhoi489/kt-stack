import SwiftUI
import KTStackKit

@MainActor
final class KTOverlayCenter: ObservableObject {
    struct ConfirmRequest: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let okLabel: String
        let danger: Bool
        let onConfirm: () -> Void
    }

    @Published var toastMessage: String?
    @Published var confirmRequest: ConfirmRequest?

    private var dismissTask: Task<Void, Never>?

    func toast(_ text: String) {
        toastMessage = text
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    func confirm(title: String, message: String, okLabel: String = "Confirm",
                 danger: Bool = true, onConfirm: @escaping () -> Void) {
        confirmRequest = ConfirmRequest(title: title, message: message, okLabel: okLabel,
                                        danger: danger, onConfirm: onConfirm)
    }
}

struct KTToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(KTColor.runDot)
            Text(message).font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(Capsule().fill(KTColor.ink))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    }
}

extension View {
    func ktOverlayHost(_ center: KTOverlayCenter) -> some View {
        overlay(alignment: .bottom) {
            if let message = center.toastMessage {
                KTToast(message: message)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if let request = center.confirmRequest {
                KTConfirmModal(title: request.title, message: request.message,
                               okLabel: request.okLabel, danger: request.danger,
                               onCancel: { center.confirmRequest = nil },
                               onConfirm: { center.confirmRequest = nil; request.onConfirm() })
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: center.toastMessage)
        .animation(.easeOut(duration: 0.15), value: center.confirmRequest?.id)
    }
}
