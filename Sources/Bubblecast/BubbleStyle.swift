import AppKit
import Combine
import CoreImage.CIFilterBuiltins

enum BubbleSize: String, CaseIterable {
    case small = "S", medium = "M", large = "L"

    var diameter: CGFloat {
        switch self {
        case .small: 160
        case .medium: 240
        case .large: 340
        }
    }
}

enum BubbleShape: String, CaseIterable {
    case circle, square, rectangle

    var symbol: String {
        switch self {
        case .circle: "circle"
        case .square: "square"
        case .rectangle: "rectangle"
        }
    }

    func dimensions(for size: BubbleSize) -> NSSize {
        NSSize(width: size.diameter, height: size.diameter * (self == .rectangle ? 0.75 : 1))
    }

    func cornerRadius(in bounds: NSRect) -> CGFloat {
        switch self {
        case .circle: min(bounds.width, bounds.height) / 2
        case .square: min(bounds.width, bounds.height) * 0.22
        case .rectangle: 18
        }
    }
}

enum BubbleFilter: String, CaseIterable {
    case none = "None", warm = "Warm", cool = "Cool", mono = "Mono"
    case bright = "Bright", vivid = "Vivid"

    func makeFilters() -> [CIFilter] {
        switch self {
        case .none: return []
        case .warm, .cool:
            let filter = CIFilter.temperatureAndTint()
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: self == .warm ? 5000 : 8000, y: 0)
            return [filter]
        case .mono: return [CIFilter.photoEffectMono()]
        case .bright, .vivid:
            let filter = CIFilter.colorControls()
            if self == .bright {
                filter.brightness = 0.06
                filter.contrast = 1.05
            } else {
                filter.saturation = 1.35
            }
            return [filter]
        }
    }
}

@MainActor
final class BubbleStyle: ObservableObject {
    @Published var size: BubbleSize { didSet { save() } }
    @Published var shape: BubbleShape { didSet { save() } }
    @Published var filter: BubbleFilter { didSet { save() } }
    var onChange: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard
        size = BubbleSize(rawValue: defaults.string(forKey: "bubble.size") ?? "") ?? .medium
        shape = BubbleShape(rawValue: defaults.string(forKey: "bubble.shape") ?? "") ?? .circle
        filter = BubbleFilter(rawValue: defaults.string(forKey: "bubble.filter") ?? "") ?? .none
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(size.rawValue, forKey: "bubble.size")
        defaults.set(shape.rawValue, forKey: "bubble.shape")
        defaults.set(filter.rawValue, forKey: "bubble.filter")
        onChange?()
    }
}
