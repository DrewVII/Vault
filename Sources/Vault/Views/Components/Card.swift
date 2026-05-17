import SwiftUI

/// Rounded card container used everywhere on the dashboard, assistant and
/// auxiliary screens. Standardises padding, corner radius, fill and stroke
/// so the layout has a uniform rhythm.
struct Card<Content: View>: View {
    let content: Content
    var padding: CGFloat = Theme.cardPadding

    init(padding: CGFloat = Theme.cardPadding, @ViewBuilder _ content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}

/// Small all-caps header used at the top of each card.
/// The optional `trailing` slot lets the caller drop in an action button
/// (e.g. "Add").
struct SectionTitle: View {
    let text: String
    var trailing: AnyView? = nil

    init(_ text: String, trailing: AnyView? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            trailing
        }
    }
}

/// "Big number" KPI block used on the dashboard cards. Renders a tiny
/// uppercase label, a large rounded numeric value and an optional caption.
struct StatLabel: View {
    let label: String
    let value: String
    var tint: Color = .primary
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            if let caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Centered "nothing here yet" view shown when a list or grid is empty.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 360)
        .padding(40)
    }
}

/// Small tinted capsule used for status badges (e.g. "Liability", "Paused").
struct Pill: View {
    let text: String
    var tint: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}
