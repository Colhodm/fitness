import Charts
import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CardTitle: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 17, weight: .semibold))
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 13)).foregroundStyle(Palette.secondary) }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    var tint: Color = Palette.orange
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 22, weight: .bold))
            Spacer()
            if let trailing {
                if let action {
                    Button(trailing, action: action).font(.system(size: 17)).foregroundStyle(tint)
                } else {
                    Text(trailing).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

struct LargeTitle: View {
    let title: String
    var eyebrow: String? = nil
    var trailing: AnyView? = nil
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow.uppercased()).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.secondary).kerning(0.3)
                }
                Text(title).font(.system(size: 34, weight: .bold))
            }
            Spacer()
            if let trailing { trailing }
        }
        .padding(.top, 8)
    }
}

struct CircleIconButton: View {
    let system: String
    var tint: Color = .white
    var size: CGFloat = 40
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(tint)
                .frame(width: size, height: size).background(Palette.field, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct ProgressBar: View {
    var value: Double
    var tint: Color
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fieldHigh)
                Capsule().fill(tint).frame(width: max(value > 0 ? height : 0, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}

struct Sparkline: View {
    var values: [Double]
    var tint: Color
    var dot = false
    var lineWidth: CGFloat = 2
    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if dot && i == values.count - 1 {
                    PointMark(x: .value("i", i), y: .value("v", v)).foregroundStyle(tint).symbolSize(30)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (values.min() ?? 0)...(max((values.max() ?? 1), (values.min() ?? 0) + 0.001)))
        .chartLegend(.hidden)
    }
}

struct PrimaryButton: View {
    let title: String
    var tint: Color = Palette.orange
    var filled = true
    var height: CGFloat = 50
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? .black : tint)
                .frame(maxWidth: .infinity).frame(height: height)
                .background(filled ? tint : Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    let title: String
    var selected: Bool
    var tint: Color = .white
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 14).frame(height: 32)
                .background(selected ? tint : Palette.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct StatColumn: View {
    let label: String
    let value: String
    var unit: String? = nil
    var valueSize: CGFloat = 17
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 13)).foregroundStyle(Palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: valueSize, weight: .semibold)).monospacedDigit()
                if let unit { Text(unit).font(.system(size: valueSize * 0.6, weight: .medium)).foregroundStyle(Palette.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RowDivider: View {
    var inset: CGFloat = 0
    var body: some View { Rectangle().fill(Palette.separator).frame(height: 0.5).padding(.leading, inset) }
}

struct SegmentedPicker<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { opt in
                Button { selection = opt.0 } label: {
                    Text(opt.1).font(.system(size: 13, weight: selection == opt.0 ? .semibold : .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(selection == opt.0 ? Palette.fieldHigh.opacity(1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct NoticeCard: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(tint)
                    .frame(width: 32, height: 32).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(message).font(.system(size: 15)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    if let actionTitle, let action {
                        Button(actionTitle, action: action).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint).padding(.top, 6)
                    }
                }
            }
        }
    }
}

extension View {
    func screenBackground() -> some View {
        self.background(Color.black.ignoresSafeArea()).scrollContentBackground(.hidden)
    }
}

/// Scrollable screen scaffold with the design's 16pt margins.
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
    }
}
