import Security
import XCTest
@testable import KTStackKit

final class HelperIdentityRequirementTests: XCTestCase {
    func testStrongRequirementPinsAnchorAndTeamWhenTeamPresent() {
        let requirement = HelperIdentity.strongRequirement(for: "com.ktstack.app", team: "44452PW7V3")
        XCTAssertNotNil(requirement)
        XCTAssertTrue(requirement!.contains("anchor apple generic"))
        XCTAssertTrue(requirement!.contains("identifier \"com.ktstack.app\""))
        XCTAssertTrue(requirement!.contains("certificate leaf[subject.OU] = \"44452PW7V3\""))
    }

    func testStrongRequirementIsNilWhenTeamAbsent() {
        XCTAssertNil(HelperIdentity.strongRequirement(for: "com.ktstack.app", team: nil))
    }

    func testStrongRequirementIsNilWhenTeamEmptyOrWhitespace() {
        XCTAssertNil(HelperIdentity.strongRequirement(for: "com.ktstack.app", team: ""))
        XCTAssertNil(HelperIdentity.strongRequirement(for: "com.ktstack.app", team: "   "))
        XCTAssertNil(HelperIdentity.strongRequirement(for: "com.ktstack.app", team: "\n\t"))
    }

    func testNormalizedTeamTrimsAndRejectsEmpty() {
        XCTAssertEqual(HelperIdentity.normalizedTeam("  ABCDE12345 "), "ABCDE12345")
        XCTAssertNil(HelperIdentity.normalizedTeam(nil))
        XCTAssertNil(HelperIdentity.normalizedTeam(""))
        XCTAssertNil(HelperIdentity.normalizedTeam("   "))
    }

    func testAbsentTeamNeverProducesSatisfiableBundleIDPinInRelease() {
        let requirement = HelperIdentity.requirement(for: "com.ktstack.app", team: nil)
        #if DEBUG
            XCTAssertEqual(requirement, "identifier \"com.ktstack.app\"")
        #else
            XCTAssertEqual(requirement, HelperIdentity.unsatisfiableRequirement)
        #endif
    }

    func testUnsatisfiableRequirementParses() {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            HelperIdentity.unsatisfiableRequirement as CFString, [], &requirement
        )
        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotNil(requirement)
    }
}
