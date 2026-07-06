import Testing
import PropertyBased
@testable import PropertyLawKit

/// v3.3.0 — tests for `checkValueSemanticPropertyLaws`. Four hand-rolled
/// conformers exercise the copy-mutate-compare law: a plain value type and a
/// correct copy-on-write type (positive controls, must pass), and a
/// reference-container leak and a broken-CoW type (negative controls, must
/// surface a violation). Fixtures mirror pbt-book Chapter 9 §9.1.3 / §9.5.

struct ValueSemanticLawsTests {

    // MARK: - Positive control — plain value type

    @Test func plainValueTypeHasValueSemantics() async throws {
        let results = try await checkValueSemanticPropertyLaws(
            for: SafeBadge.self,
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.isViolation == false })
        #expect(results[0].tier == .strict)
        #expect(results[0].protocolLaw == "ValueSemantic.copyMutationDoesNotLeak")
    }

    // MARK: - Positive control — correct copy-on-write

    @Test func correctCopyOnWriteHasValueSemantics() async throws {
        // The crucial guard: a properly-implemented CoW container clones its
        // storage on the first mutation of a shared copy, so the original is
        // never touched. The law must NOT false-positive on it.
        let results = try await checkValueSemanticPropertyLaws(
            for: SafeBuffer.self,
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.isViolation == false })
    }

    // MARK: - Negative control — reference-container leak (Chapter 9 §9.1.3)

    @Test func referenceContainerLeakIsDetected() async throws {
        // A struct wrapping a shared class reference: copying the struct shares
        // the reference, so mutating the copy bleeds into the original.
        await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkValueSemanticPropertyLaws(
                for: LeakyBadge.self,
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }

    // MARK: - Negative control — broken copy-on-write (Chapter 9 §9.2.2)

    @Test func brokenCopyOnWriteIsDetected() async throws {
        // Intends CoW over a class storage but omits the
        // `isKnownUniquelyReferenced` guard, so copies share storage.
        await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkValueSemanticPropertyLaws(
                for: BrokenBuffer.self,
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }
}

// MARK: - Fixtures: plain value type (positive control)

struct SafeBadge: ValueSemantic, Sendable {
    var value: Int = 0

    static func makeProbe() -> SafeBadge { SafeBadge() }

    enum Mutation: CaseIterable, Sendable { case increment }

    static func apply(_ mutation: Mutation, to target: inout SafeBadge) {
        switch mutation {
        case .increment: target.value += 1
        }
    }
}

// MARK: - Fixtures: reference-container leak (negative control)

struct LeakyBadge: ValueSemantic, Sendable {

    /// A shared, mutable reference — the escape hatch. `@unchecked Sendable`
    /// because it is deliberately unsafe (that is the bug under test).
    final class Box: @unchecked Sendable {
        var value: Int
        init(_ value: Int) { self.value = value }
    }

    var box: Box = Box(0)

    static func == (lhs: LeakyBadge, rhs: LeakyBadge) -> Bool {
        lhs.box.value == rhs.box.value
    }

    static func makeProbe() -> LeakyBadge { LeakyBadge() }

    enum Mutation: CaseIterable, Sendable { case increment }

    static func apply(_ mutation: Mutation, to target: inout LeakyBadge) {
        switch mutation {
        // Mutates through the shared reference — a copy's mutation is visible
        // through the original.
        case .increment: target.box.value += 1
        }
    }
}

// MARK: - Fixtures: broken copy-on-write (negative control)

struct BrokenBuffer: ValueSemantic, Sendable {

    final class Storage: @unchecked Sendable {
        var bytes: [UInt8]
        init(_ bytes: [UInt8] = []) { self.bytes = bytes }
        func clone() -> Storage { Storage(bytes) }
    }

    var storage: Storage = Storage()

    static func == (lhs: BrokenBuffer, rhs: BrokenBuffer) -> Bool {
        lhs.storage.bytes == rhs.storage.bytes
    }

    static func makeProbe() -> BrokenBuffer { BrokenBuffer() }

    enum Mutation: CaseIterable, Sendable { case appendOne }

    static func apply(_ mutation: Mutation, to target: inout BrokenBuffer) {
        switch mutation {
        // BUG: no `isKnownUniquelyReferenced` guard — shared storage is
        // mutated in place, so the original observes the copy's append.
        case .appendOne: target.storage.bytes.append(1)
        }
    }
}

// MARK: - Fixtures: correct copy-on-write (positive control)

struct SafeBuffer: ValueSemantic, Sendable {

    final class Storage: @unchecked Sendable {
        var bytes: [UInt8]
        init(_ bytes: [UInt8] = []) { self.bytes = bytes }
        func clone() -> Storage { Storage(bytes) }
    }

    var storage: Storage = Storage()

    static func == (lhs: SafeBuffer, rhs: SafeBuffer) -> Bool {
        lhs.storage.bytes == rhs.storage.bytes
    }

    static func makeProbe() -> SafeBuffer { SafeBuffer() }

    enum Mutation: CaseIterable, Sendable { case appendOne }

    static func apply(_ mutation: Mutation, to target: inout SafeBuffer) {
        switch mutation {
        case .appendOne:
            // Correct CoW: clone shared storage before mutating, so a copy's
            // append never touches the original.
            if !isKnownUniquelyReferenced(&target.storage) {
                target.storage = target.storage.clone()
            }
            target.storage.bytes.append(1)
        }
    }
}
