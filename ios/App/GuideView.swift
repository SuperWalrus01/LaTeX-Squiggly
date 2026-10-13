import SwiftUI

/// One short lesson on the keyboard. Lessons with a check are done when the
/// practice box shows the user did it; the rest are done when they say so.
struct Lesson: Identifiable {
    let id: Int
    let title: String
    let summary: String
    let symbol: String
    let mascot: String
    let steps: [String]
    var tip: String?
    /// Whether the user types in a practice box.
    var practice = true
    /// Done, given the practice text and every character it has held.
    var check: ((String, Set<Character>) -> Bool)?
    var opensSettings = false
}

extension Lesson {
    static let all: [Lesson] = [
        Lesson(id: 0, title: "Turn it on", summary: "Add the keyboard in Settings",
               symbol: "keyboard", mascot: "MascotHello",
               steps: ["Open Settings, then General, Keyboard, Keyboards.",
                       "Tap Add New Keyboard and choose LaTeX Squiggly.",
                       "Optional: tap LaTeX Squiggly and turn on Allow Full Access. Copy needs it to put images on the clipboard, and the keyboard needs it to read this app's settings."],
               tip: "Nothing you type leaves your phone, with Full Access or without.",
               practice: false, opensSettings: true),
        Lesson(id: 1, title: "Your first symbol", summary: "Type LaTeX, press space, get α",
               symbol: "character.cursor.ibeam", mascot: "MascotLaptop",
               steps: ["Hold [globe] below the keys and pick LaTeX Squiggly.",
                       "Type [\\] `alpha`, then press [space]."],
               tip: "Every command works this way: `\\to` gives →, and `\\infty` gives ∞.",
               check: { text, _ in text.contains("α") }),
        Lesson(id: 2, title: "Let it finish for you", summary: "Pick a command from the bar",
               symbol: "sparkles", mascot: "MascotIdea",
               steps: ["Type [\\] `th`.",
                       "Tap θ in the bar above the keys."],
               tip: "The bar offers the closest matches as soon as you type [\\].",
               check: { text, _ in text.contains("θ") }),
        Lesson(id: 3, title: "Changed your mind?", summary: "Delete brings the LaTeX back",
               symbol: "arrow.uturn.backward", mascot: "MascotReading",
               steps: ["Type [\\] `pi`, then [space]. It becomes π.",
                       "Press [delete] straight away. The LaTeX comes back, and [space] now leaves it as it is."],
               check: { text, seen in seen.contains("π") && text.contains("\\pi") }),
        Lesson(id: 4, title: "Greek and symbols", summary: "One tap on the ∑ page",
               symbol: "sum", mascot: "MascotBooks",
               steps: ["Tap [∑] at the right of the bar.",
                       "Tap [∞].",
                       "Hold a key, like [≤] or the letter [e], for related symbols and accents."],
               tip: "Tap [∑] again, or [ABC], to go back to the letters.",
               check: { text, _ in text.contains("∞") }),
        Lesson(id: 5, title: "Powers and fractions", summary: "Fill in the boxes, space to move on",
               symbol: "x.squareroot", mascot: "MascotWalking",
               steps: ["Type `x`, then tap [x²] in the bar.",
                       "Type `2`, then press [space] to step out of the box.",
                       "Press [space] once more and it becomes x²."],
               tip: "[a⁄b] works the same way: [space] moves from the top box to the bottom one.",
               check: { text, _ in text.contains("²") || text.contains("½") }),
        Lesson(id: 6, title: "Equations as images", summary: "Between $ signs, ready to paste",
               symbol: "photo", mascot: "MascotPeeking",
               steps: ["Tap [$…$] in the bar.",
                       "Type `x^2 + y^2 = z^2`.",
                       "The bar shows it typeset. Tap it to see it large, or tap Copy and paste it into any chat."],
               tip: "Copy needs Allow Full Access, from the first lesson.",
               check: { text, _ in text.range(of: #"\$[^$]*\^[^$]*\$"#, options: .regularExpression) != nil }),
        Lesson(id: 7, title: "Keep it as LaTeX", summary: "For LaTeX documents",
               symbol: "chevron.left.forwardslash.chevron.right", mascot: "MascotLaptop",
               steps: ["Tap [LaTeX] at the left of the bar. It turns orange.",
                       "Type [\\] `beta`, then [space]. It stays as LaTeX.",
                       "Tap [LaTeX] again when you're done."],
               tip: "Useful in Overleaf and other LaTeX editors, where maths isn't always between $ signs.",
               check: { text, _ in text.contains("\\beta") }),
        Lesson(id: 8, title: "Emoji", summary: "Right inside the keyboard",
               symbol: "face.smiling", mascot: "MascotWalking",
               steps: ["Tap [emoji] next to [123].",
                       "Tap any emoji. The icons along the bottom jump to a category.",
                       "Tap [ABC] to go back to the letters."],
               tip: "The emoji you use most come first next time.",
               check: { text, _ in text.unicodeScalars.contains { $0.properties.isEmojiPresentation } }),
        Lesson(id: 9, title: "Render from anywhere", summary: "Selections, Share and Messages",
               symbol: "square.and.arrow.up", mascot: "MascotCelebrate",
               steps: ["Select text with maths in it, in any app, and tap Copy in the bar.",
                       "Or tap Share, then LaTeX Squiggly, to render it right there.",
                       "In Messages, open the app drawer and pick LaTeX Squiggly to send an equation as a picture."],
               tip: "The Render tab in this app takes equations too long for the bar.",
               practice: false),
    ]
}

/// The lessons done so far, kept between launches.
final class GuideProgress: ObservableObject {
    @AppStorage("guideDone") private var stored = ""

    var done: Set<Int> {
        Set(stored.split(separator: ",").compactMap { Int($0) })
    }

    func complete(_ lesson: Lesson) {
        guard !done.contains(lesson.id) else { return }
        objectWillChange.send()
        stored = (done.union([lesson.id])).sorted().map(String.init).joined(separator: ",")
    }

    func reset() {
        objectWillChange.send()
        stored = ""
    }

    /// The first lesson not yet done.
    var next: Lesson? { Lesson.all.first { !done.contains($0.id) } }
}

// MARK: - The guide's home

struct GuideView: View {
    @EnvironmentObject private var progress: GuideProgress
    @State private var open: Lesson?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                progressCard
                VStack(spacing: 10) {
                    SectionTitle("Lessons")
                    ForEach(Lesson.all) { lesson in
                        Button { open = lesson } label: { row(lesson) }
                            .buttonStyle(RowPressStyle())
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Color.paper.ignoresSafeArea())
        .fullScreenCover(item: $open) { lesson in
            LessonFlow(current: lesson) { open = nil }
                .environmentObject(progress)
        }
        #if DEBUG
        .onAppear {
            if let n = ProcessInfo.processInfo.environment["PREVIEW_LESSON"].flatMap(Int.init) {
                open = Lesson.all[n]
            }
        }
        #endif
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Wordmark().frame(height: 54, alignment: .leading)
                Text("Write maths anywhere.")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer(minLength: 0)
            Image("MascotHello")
                .resizable()
                .scaledToFit()
                .frame(height: 104)
                .accessibilityHidden(true)
        }
        .padding(.top, 12)
    }

    private var progressCard: some View {
        let count = progress.done.count, total = Lesson.all.count
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(count == 0 ? "Learn the keyboard" : count == total ? "You know it all" : "Keep going")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.ink)
                Text(count == 0 ? "Ten short lessons, about three minutes."
                     : "\(count) of \(total) lessons done.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.inkSoft)
            }
            ProgressBar(value: Double(count) / Double(total))
            if let next = progress.next {
                Button { open = next } label: {
                    Label(count == 0 ? "Start" : "Continue: \(next.title)", systemImage: "play.fill")
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .card(padding: 20)
    }

    private func row(_ lesson: Lesson) -> some View {
        let done = progress.done.contains(lesson.id)
        return HStack(spacing: 14) {
            IconTile(symbol: lesson.symbol, done: done)
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.ink)
                Text(lesson.summary)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.inkSoft.opacity(0.6))
        }
        .card(padding: 14)
    }
}

/// Rows shrink a touch when pressed, as cards do in iOS.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - A lesson

/// The lessons one after another, sliding in from the right, until the
/// user closes the guide or finishes the last one.
private struct LessonFlow: View {
    @State var current: Lesson
    let close: () -> Void

    var body: some View {
        LessonView(lesson: current) { next in
            if let next {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { current = next }
            } else {
                close()
            }
        }
        .id(current.id)
        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
    }
}

struct LessonView: View {
    let lesson: Lesson
    /// Goes to another lesson, or closes the guide with nil.
    let go: (Lesson?) -> Void

    @EnvironmentObject private var progress: GuideProgress
    @Environment(\.openURL) private var openURL
    @State private var text = ""
    @State private var seen: Set<Character> = []
    @State private var done = false
    @FocusState private var typing: Bool

    private var next: Lesson? { Lesson.all.first { $0.id == lesson.id + 1 } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    stepsCard
                    if lesson.practice { practiceCard }
                    if let tip = lesson.tip { tipCard(tip) }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.never)
            bottomBar
        }
        .background(Color.paper.ignoresSafeArea())
        .onAppear {
            done = false
            if lesson.practice {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { typing = true }
            }
        }
        .onChange(of: text) { value in
            seen.formUnion(value)
            if let check = lesson.check, !done, check(value, seen) { finish() }
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { go(nil) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.card))
                    .overlay(Circle().strokeBorder(Color.rule))
            }
            .accessibilityLabel("Close")
            ProgressBar(value: Double(lesson.id + (done ? 1 : 0)) / Double(Lesson.all.count))
            Text("\(lesson.id + 1)/\(Lesson.all.count)")
                .font(.system(.footnote, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(Color.inkSoft)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LESSON \(lesson.id + 1)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Color.squiggle)
                Text(lesson.title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(done ? "MascotCelebrate" : lesson.mascot)
                .resizable()
                .scaledToFit()
                .frame(height: 64)
                .scaleEffect(done ? 1.08 : 1)
                .animation(.spring(response: 0.4, dampingFraction: 0.5), value: done)
                .accessibilityHidden(true)
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(lesson.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.squiggle))
                        .padding(.top, 1)
                    Instruction(text: step)
                }
            }
            if lesson.opensSettings {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .padding(.top, 4)
            }
        }
        .card()
    }

    private var practiceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(done ? "Done" : "Try it here")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(done ? Color.squiggle : Color.inkSoft)
                Spacer()
                if !text.isEmpty {
                    Button("Clear") { text = ""; seen = [] }
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.squiggle)
                }
            }
            TextField("Tap here to bring up the keyboard", text: $text, axis: .vertical)
                .font(.system(size: 22))
                .lineLimit(2...5)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($typing)
                .foregroundStyle(Color.ink)
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(done ? Color.squiggle : typing ? Color.squiggle.opacity(0.4) : .clear,
                              lineWidth: 2)
        )
        .animation(.easeOut(duration: 0.2), value: done)
    }

    private func tipCard(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Color.squiggle)
                .font(.system(size: 17))
                .padding(.top, 3)
            Instruction(text: tip, font: .system(.subheadline, design: .rounded))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.squiggle.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// What comes next: a quiet skip while practising, then the way on.
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if done || lesson.check == nil {
                HStack(spacing: 10) {
                    if done {
                        Label("Nice!", systemImage: "checkmark.circle.fill")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Color.squiggle)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Button {
                        if !done { progress.complete(lesson) }
                        go(next)
                    } label: {
                        Text(next == nil ? "Finish" : done ? "Next lesson" : "Got it")
                    }
                    .buttonStyle(PillButtonStyle())
                }
            } else {
                Button("Skip this one") {
                    progress.complete(lesson)
                    go(next)
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.inkSoft)
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.paper.shadow(color: Color.ink.opacity(0.06), radius: 8, y: -4))
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: done)
    }

    private func finish() {
        done = true
        progress.complete(lesson)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
