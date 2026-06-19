import SwiftUI

public enum KTType {
    public static let screenTitle = Font.system(size: 25, weight: .bold)
    public static let modalTitle = Font.system(size: 20, weight: .bold)
    public static let cardName = Font.system(size: 15, weight: .semibold)
    public static let rowName = Font.system(size: 14.5, weight: .semibold)
    public static let label = Font.system(size: 14, weight: .semibold)
    public static let body = Font.system(size: 14)
    public static let control = Font.system(size: 13, weight: .medium)
    public static let sub = Font.system(size: 12.5)
    public static let sub13 = Font.system(size: 13)
    public static let caption = Font.system(size: 11.5)
    public static let sectionLabel = Font.system(size: 11, weight: .bold)
    public static let settingsLabel = Font.system(size: 12, weight: .bold)
    public static let mono = Font.system(size: 13, design: .monospaced)
    public static let monoSmall = Font.system(size: 12.5, design: .monospaced)

    public static let screenTitleTracking: CGFloat = -0.5
    public static let sectionLabelTracking: CGFloat = 0.6
}
