import SwiftUI

/// A list of numbers SwiftUI can animate between.
///
/// This is what makes a drawing able to become a different drawing rather than
/// being replaced by one. SwiftUI interpolates a view's `animatableData` frame
/// by frame, and `Double` and `CGPoint` already conform, but a diagram has an
/// arbitrary number of coordinates in it and there is no stock type for "some
/// doubles". So: the smallest possible `VectorArithmetic` over an array.
///
/// The interesting case is a length change, because the old diagram and the new
/// one rarely have the same number of parts. Every operation pads the shorter
/// side rather than refusing, which means a node that did not exist a moment ago
/// animates out from wherever index arithmetic puts it instead of the whole
/// morph failing. That is a deliberate trade: a slightly arbitrary path for one
/// new element beats no animation at all for the other twenty.
struct AnimatableVector: VectorArithmetic, Equatable {
    var values: [Double]

    init(_ values: [Double] = []) { self.values = values }

    static var zero: AnimatableVector { AnimatableVector() }

    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        AnimatableVector(zip(padded(lhs, rhs).0, padded(lhs, rhs).1).map(+))
    }

    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        AnimatableVector(zip(padded(lhs, rhs).0, padded(lhs, rhs).1).map(-))
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    /// Pad the shorter side with zeroes so the two line up.
    private static func padded(
        _ lhs: AnimatableVector, _ rhs: AnimatableVector
    ) -> ([Double], [Double]) {
        let count = max(lhs.values.count, rhs.values.count)
        return (
            lhs.values + Array(repeating: 0, count: count - lhs.values.count),
            rhs.values + Array(repeating: 0, count: count - rhs.values.count)
        )
    }
}
