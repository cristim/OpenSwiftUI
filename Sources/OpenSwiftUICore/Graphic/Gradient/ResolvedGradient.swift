//
//  ResolvedGradient.swift
//  OpenSwiftUICore
//

//  Audited for 6.0.87
//  Status: Empty

public import CoreGraphics

package struct ResolvedGradient: Equatable {
    package enum ColorSpace {
        case device
        case linear
        case perceptual

        func mix(_ lhs: Color.Resolved, _ rhs: Color.Resolved, by fraction: Float) -> Color.Resolved {
            _openSwiftUIUnimplementedFailure()
        }
    }
}

@frozen
public struct Gradient {
    @frozen
    public struct Stop {
        public var color: Color
        public var location: CGFloat

        public init(color: Color, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }

    public var stops: [Stop]

    public init(stops: [Stop]) {
        self.stops = stops
    }

    public init(colors: [Color]) {
        let denominator = CGFloat(max(colors.count - 1, 1))
        self.stops = colors.enumerated().map { index, color in
            Stop(color: color, location: CGFloat(index) / denominator)
        }
    }

    package init(_ resolved: ResolvedGradient) {
        self.stops = []
    }
}
