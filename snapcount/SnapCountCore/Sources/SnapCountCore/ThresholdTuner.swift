import Foundation

/// One labelled example: a similarity score, and whether it really was the target person.
public struct LabelledScore: Sendable, Equatable {
    public let similarity: Float
    public let isTarget: Bool

    public init(similarity: Float, isTarget: Bool) {
        self.similarity = similarity
        self.isTarget = isTarget
    }
}

public struct ThresholdResult: Sendable, Equatable {
    public let threshold: Float
    public let truePositives: Int
    public let falsePositives: Int
    public let trueNegatives: Int
    public let falseNegatives: Int

    public var precision: Double {
        let denominator = truePositives + falsePositives
        return denominator == 0 ? 1 : Double(truePositives) / Double(denominator)
    }

    public var recall: Double {
        let denominator = truePositives + falseNegatives
        return denominator == 0 ? 1 : Double(truePositives) / Double(denominator)
    }

    public var f1: Double {
        let denominator = precision + recall
        return denominator == 0 ? 0 : 2 * precision * recall / denominator
    }
}

/// Sweeps the match threshold against labelled data so the cut-off is chosen from evidence
/// rather than from a number copied out of a paper.
///
/// This matters more than usual here. Published face-recognition thresholds are derived from
/// adult benchmark sets, and this app has to separate one young child from other young
/// children, which is materially harder.
public struct ThresholdTuner: Sendable {

    public init() {}

    public func sweep(
        _ scores: [LabelledScore],
        from lower: Float = 0.0,
        to upper: Float = 1.0,
        step: Float = 0.01
    ) -> [ThresholdResult] {
        guard !scores.isEmpty, step > 0, upper >= lower else { return [] }

        var results: [ThresholdResult] = []
        var threshold = lower
        while threshold <= upper {
            var tp = 0, fp = 0, tn = 0, fn = 0
            for score in scores {
                let predicted = score.similarity >= threshold
                switch (predicted, score.isTarget) {
                case (true, true): tp += 1
                case (true, false): fp += 1
                case (false, false): tn += 1
                case (false, true): fn += 1
                }
            }
            results.append(ThresholdResult(
                threshold: threshold,
                truePositives: tp, falsePositives: fp,
                trueNegatives: tn, falseNegatives: fn))
            threshold += step
        }
        return results
    }

    /// Threshold that maximises recall subject to a precision floor.
    ///
    /// Precision-first rather than best-F1 on purpose. A false positive means the app counted
    /// a photo of someone else's child as the user's, which is the failure that actually
    /// matters. A false negative is just a slightly low number.
    ///
    /// Returns nil when no threshold reaches the floor, which is itself the useful signal:
    /// the enrolled reference is not discriminative enough and needs better sample photos.
    ///
    /// Candidates must produce at least one true positive. Without that guard a threshold set
    /// above every score trivially scores perfect precision on an empty positive set, and the
    /// tuner would happily recommend a cut-off that matches nothing at all.
    public func recommend(
        from scores: [LabelledScore],
        minimumPrecision: Double = 0.98
    ) -> ThresholdResult? {
        let qualifying = sweep(scores)
            .filter { $0.truePositives > 0 }
            .filter { $0.precision >= minimumPrecision }
        guard let bestRecall = qualifying.map(\.recall).max() else { return nil }

        // Many thresholds usually tie on recall: everything in the gap between the highest
        // impostor and the lowest genuine score. Take the middle of that plateau rather than
        // an edge. The low edge sits a hair above the worst impostor in a small tuning set, so
        // the first unseen child who scores slightly higher gets counted. The high edge does
        // the same to her own harder photos. The midpoint leaves margin on both sides.
        let plateau = qualifying.filter { $0.recall == bestRecall }
        guard let low = plateau.first?.threshold, let high = plateau.last?.threshold else {
            return nil
        }
        let middle = (low + high) / 2
        return plateau.min { abs($0.threshold - middle) < abs($1.threshold - middle) }
    }
}
