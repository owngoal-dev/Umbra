import SwiftUI

enum TVAppearance {
    static let background = Color(red: 0.055, green: 0.065, blue: 0.085)
}

struct TVFocusStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVButtonSurface(configuration: configuration)
    }

    private struct TVButtonSurface: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isFocused) private var focused
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(configuration.role == .destructive ? Color(red: 1, green: 0.48, blue: 0.48) : .white)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .background(.white.opacity(focused ? 0.16 : 0.045), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(focused ? 0.75 : 0), lineWidth: 2)
                }
                .opacity(enabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.99 : (focused ? 1.015 : 1))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focused)
        }
    }
}

struct TVToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 24) {
                configuration.label
                Spacer()
                Text(localized(configuration.isOn ? "Enabled" : "Disabled"))
                    .font(.system(size: 25)).foregroundStyle(.secondary)
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? Color(red: 0.6, green: 0.78, blue: 1) : .secondary)
            }
        }
        .accessibilityValue(localized(configuration.isOn ? "Enabled" : "Disabled"))
    }
}

struct TVList<Content: View>: View {
    var horizontalInset: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, 24)
        }
        .buttonStyle(TVFocusStyle())
        .toggleStyle(TVToggleStyle())
    }
}

struct TVSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title).font(.system(size: 23, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(2).padding(.top, 10).padding(.horizontal, 4)
            }
            content
        }
        .padding(.bottom, 12)
    }
}

struct TVPage<Actions: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 42, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 24)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            if Actions.self != EmptyView.self {
                HStack(spacing: 18) { actions }
                    .buttonStyle(TVFocusStyle())
                    .padding(.horizontal, 24)
            }
            content
        }
        .frame(maxWidth: 1240, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 32)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .background(TVAppearance.background.ignoresSafeArea())
        .navigationBarHidden(true)
    }
}

struct TVRow: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var disclosure = true

    var body: some View {
        HStack(spacing: 24) {
            if let symbol {
                Image(systemName: symbol).frame(width: 44).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 29, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(.system(size: 23)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 16)
            if disclosure {
                Image(systemName: "chevron.right").font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }
}

struct TVEmptyView: View {
    let title: String
    let symbol: String
    var message: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: symbol).font(.system(size: 56)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(localized(title)).font(.title2)
            if let message {
                Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

private struct TVDetailModifier: ViewModifier {
    let title: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title).font(.system(size: 42, weight: .semibold)).padding(.horizontal, 24)
            content
        }
        .frame(maxWidth: 1240, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 32)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .background(TVAppearance.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .onExitCommand { dismiss() }
    }
}

extension View {
    func tvDetailTitle(_ title: String) -> some View {
        modifier(TVDetailModifier(title: title))
    }
}
