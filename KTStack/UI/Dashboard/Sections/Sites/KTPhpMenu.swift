import SwiftUI
import KTStackKit

struct KTPhpMenu: View {
    let current: String
    let versions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        KTDropdown(width: 150,
                   options: versions.map { version in
                       KTDropdownOption(label: "PHP \(version)", active: version == current) { onSelect(version) }
                   }) {
            KTDropdownChevronLabel(text: "PHP \(current)")
        }
        .fixedSize()
        .ktTip("Switch the PHP version for this site")
    }
}
