import Testing

@testable import OpenPromptrCore

@Test("A tagged version strips the leading v")
func marketingVersionStripsPrefix() {
    #expect(VersionInfo.marketingVersion(fromTag: "v1.1.0") == "1.1.0")
}

@Test("A version without a v prefix is accepted as-is")
func marketingVersionAcceptsBareVersion() {
    #expect(VersionInfo.marketingVersion(fromTag: "1.1.0") == "1.1.0")
}

@Test("A git describe suffix is rejected rather than half-parsed")
func marketingVersionRejectsDescribeSuffix() {
    #expect(VersionInfo.marketingVersion(fromTag: "v1.1.0-3-gabc1234") == nil)
}

@Test("Non-numeric or malformed tags are rejected")
func marketingVersionRejectsMalformedTags() {
    #expect(VersionInfo.marketingVersion(fromTag: "not-a-tag") == nil)
    #expect(VersionInfo.marketingVersion(fromTag: "v1.1") == nil)
    #expect(VersionInfo.marketingVersion(fromTag: "") == nil)
}

@Test("Display string combines version and build")
func displayStringCombinesVersionAndBuild() {
    #expect(VersionInfo.displayString(version: "1.1.0", build: "42") == "1.1.0 (42)")
}
