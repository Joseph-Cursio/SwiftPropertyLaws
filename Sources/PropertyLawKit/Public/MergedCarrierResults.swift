/// Folds one `CheckResult` per law out of many per-carrier runs.
///
/// Keyed on `protocolLaw` and ordered by first appearance, so the merged output
/// reads in the same order a single run of the suite would.
struct MergedCarrierResults {
    private var order: [String] = []
    private var byLaw: [String: CheckResult] = [:]
    private var carriersVisited = 0
    private let spaceSize: Int

    private(set) var sawViolation = false

    init(spaceSize: Int) {
        self.spaceSize = spaceSize
    }

    mutating func absorb(_ results: [CheckResult], carrier: String) {
        carriersVisited += 1
        for result in results {
            guard var running = byLaw[result.protocolLaw] else {
                order.append(result.protocolLaw)
                byLaw[result.protocolLaw] = attributing(result, to: carrier)
                sawViolation = sawViolation || result.isViolation
                continue
            }
            // A law that already failed keeps its first (smallest) carrier;
            // otherwise accumulate the trials and take this carrier's outcome.
            if running.isViolation {
                continue
            }
            running.trials += result.trials
            if result.isViolation {
                let attributed = attributing(result, to: carrier)
                running.outcome = attributed.outcome
            }
            byLaw[result.protocolLaw] = running
            sawViolation = sawViolation || result.isViolation
        }
    }

    /// Name the carrier in the counterexample. The address is what makes the
    /// case reproducible; the law's own text is what explains it.
    private func attributing(_ result: CheckResult, to carrier: String) -> CheckResult {
        guard case .failed(let counterexample) = result.outcome else { return result }
        var attributed = result
        attributed.outcome = .failed(counterexample: "\(carrier) — \(counterexample)")
        return attributed
    }

    func assembled() -> [CheckResult] {
        order.compactMap { name in
            guard var result = byLaw[name] else { return nil }
            result.coverage = SpaceCoverage(casesRun: carriersVisited, spaceSize: spaceSize)
            return result
        }
    }
}
