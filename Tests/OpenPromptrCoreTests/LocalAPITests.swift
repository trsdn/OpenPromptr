import Testing

@testable import OpenPromptrCore

@Test("A transform patch only changes the fields it mentions")
func transformPatchAppliesPartially() {
    let base = DisplayTransform(
        rotation: .degrees0,
        mirrorHorizontally: true,
        mirrorVertically: false
    )

    let rotationOnly = TransformPatch(rotation: 180).apply(to: base)
    #expect(rotationOnly.rotation == .degrees180)
    #expect(rotationOnly.mirrorHorizontally == true)
    #expect(rotationOnly.mirrorVertically == false)

    let mirrorOnly = TransformPatch(mirrorV: true).apply(to: base)
    #expect(mirrorOnly.rotation == .degrees0)
    #expect(mirrorOnly.mirrorVertically == true)

    let empty = TransformPatch().apply(to: base)
    #expect(empty == base)
}

@Test("An unrecognized rotation value is ignored rather than rejecting the patch")
func transformPatchIgnoresInvalidRotation() {
    let base = DisplayTransform(rotation: .degrees90)
    let patched = TransformPatch(rotation: 45, mirrorH: false).apply(to: base)

    #expect(patched.rotation == .degrees90)
    #expect(patched.mirrorHorizontally == false)
}

@Test("Token comparison accepts only an exact match")
func tokenMatchesExactly() {
    #expect(LocalAPIAuth.tokenMatches(provided: "secret", expected: "secret"))
    #expect(!LocalAPIAuth.tokenMatches(provided: "secre", expected: "secret"))
    #expect(!LocalAPIAuth.tokenMatches(provided: "secret ", expected: "secret"))
    #expect(!LocalAPIAuth.tokenMatches(provided: "wrong", expected: "secret"))
    #expect(!LocalAPIAuth.tokenMatches(provided: nil, expected: "secret"))
}

@Test("A request is rejected for carrying any Origin header, regardless of case or value")
func originHeaderIsRejectedRegardlessOfValue() {
    #expect(LocalAPIAuth.isOriginRejected(headers: ["Origin": "http://example.com"]))
    #expect(LocalAPIAuth.isOriginRejected(headers: ["origin": "null"]))
    #expect(LocalAPIAuth.isOriginRejected(headers: ["ORIGIN": ""]))
    #expect(!LocalAPIAuth.isOriginRejected(headers: ["Authorization": "Bearer x"]))
    #expect(!LocalAPIAuth.isOriginRejected(headers: [:]))
}

@Test("A bearer token is extracted only from a well-formed Authorization header")
func bearerTokenExtraction() {
    #expect(LocalAPIAuth.bearerToken(fromAuthorizationHeader: "Bearer abc123") == "abc123")
    #expect(LocalAPIAuth.bearerToken(fromAuthorizationHeader: "Basic abc123") == nil)
    #expect(LocalAPIAuth.bearerToken(fromAuthorizationHeader: nil) == nil)
    #expect(LocalAPIAuth.bearerToken(fromAuthorizationHeader: "") == nil)
}
