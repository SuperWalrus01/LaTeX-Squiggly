import SwiftUI

/// The keyboard's settings, help and the small print, as cards of rows.
struct SettingsView: View {
    @EnvironmentObject private var progress: GuideProgress
    @Environment(\.openURL) private var openURL
    @State private var autoCapitals = SharedSettings.autoCapitals

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ScreenTitle(title: "Settings", mascot: "MascotBackpack")

                    group("Keyboard") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $autoCapitals) {
                                rowLabel("Automatic capitals", symbol: "textformat.size")
                            }
                            .tint(.squiggle)
                            .onChange(of: autoCapitals) { SharedSettings.autoCapitals = $0 }
                            Text("A capital at the start of each sentence. Off by default, since x and X mean different things in maths. Needs Allow Full Access.")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Color.inkSoft)
                                .padding(.leading, 46)
                        }
                        divider
                        linkRow("Keyboards in iOS Settings", symbol: "gear") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }

                    group("Help") {
                        linkRow("Start the guide again", symbol: "arrow.counterclockwise") { progress.reset() }
                        divider
                        linkRow("Help and feedback", symbol: "bubble.left.and.bubble.right") { openURL(Links.support) }
                    }

                    group("Privacy") {
                        HStack(alignment: .top, spacing: 14) {
                            IconTile(symbol: "lock.fill", size: 32)
                            Text("Nothing you type leaves your phone. Full Access is used only to put rendered images on the clipboard and to read these settings.")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Color.ink)
                        }
                        divider
                        linkRow("Privacy policy", symbol: "hand.raised") { openURL(Links.privacy) }
                    }

                    group("About") {
                        NavigationLink { AcknowledgementsView() } label: {
                            HStack {
                                rowLabel("Acknowledgements", symbol: "heart")
                                Spacer()
                                chevron
                            }
                        }
                        divider
                        HStack {
                            rowLabel("Version", symbol: "info.circle")
                            Spacer()
                            Text(Links.version)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Color.inkSoft)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Color.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.squiggle)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            SectionTitle(title)
            VStack(alignment: .leading, spacing: 14) { content() }
                .card(padding: 16)
        }
    }

    private func rowLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, size: 32)
            Text(title)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(Color.ink)
        }
    }

    private func linkRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                rowLabel(title, symbol: symbol)
                Spacer()
                chevron
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.bold))
            .foregroundStyle(Color.inkSoft.opacity(0.6))
    }

    private var divider: some View {
        Rectangle().fill(Color.rule).frame(height: 1).padding(.leading, 46)
    }
}

/// A screen's big rounded title, with the mascot beside it.
struct ScreenTitle: View {
    let title: String
    let mascot: String

    var body: some View {
        HStack(alignment: .bottom) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
            Spacer()
            Image(mascot)
                .resizable()
                .scaledToFit()
                .frame(height: 70)
                .accessibilityHidden(true)
        }
        .padding(.top, 12)
    }
}

/// A section heading in the brand's rounded type, for lists.
func heading(_ text: String) -> some View {
    Text(text)
        .font(.system(.footnote, design: .rounded).weight(.semibold))
        .foregroundStyle(Color.inkSoft)
}
