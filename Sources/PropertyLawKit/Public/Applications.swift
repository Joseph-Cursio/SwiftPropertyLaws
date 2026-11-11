import Foundation

/// Counts how often a conditional law's antecedent held.
///
/// Four of the six laws here are conditional — `guard compare(a, b), compare(b, c)`,
/// `guard first == second`, and so on — and **a conditional law whose antecedent
/// never fires reports `.passed` having tested nothing.** That is not a
/// hypothetical: `congruence` needs the generator to produce two equal values,
/// which over a wide domain is close to never, so the law goes green for free on
/// exactly the callers most likely to need it.
///
/// This is the same fault `checkInvariantIsFalsifiable` exists to catch, one
/// level down: there the *invariant* forbids nothing, here the *law* applies to
/// nothing. Both are specifications that cannot fail.
final class Applications: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() { lock.lock(); count += 1; lock.unlock() }

    var recorded: Int { lock.lock(); defer { lock.unlock() }; return count }
}
