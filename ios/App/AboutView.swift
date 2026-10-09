import SwiftUI

/// Where the app points for privacy and help, and its version. App Review
/// wants the privacy policy reachable from inside the app as well as from
/// the store listing.
enum Links {
    static let privacy = URL(string: "https://superwalrus01.github.io/LaTeX-Squiggly/privacy.html")!
    static let support = URL(string: "https://github.com/SuperWalrus01/LaTeX-Squiggly/issues")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// The open-source code and fonts the app ships, with the notices their
/// licences ask to be included.
struct AcknowledgementsView: View {
    private static let mit = """
        Permission is hereby granted, free of charge, to any person obtaining a copy \
        of this software and associated documentation files (the "Software"), to deal \
        in the Software without restriction, including without limitation the rights \
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell \
        copies of the Software, and to permit persons to whom the Software is \
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all \
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, \
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE \
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER \
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE \
        SOFTWARE.
        """

    var body: some View {
        List {
            Section(header: heading("SwiftMath")) {
                Text("Typesets every rendered equation. MIT License.\n\nCopyright (c) 2023 Computer Inspirations")
            }
            .listRowBackground(Color.card)
            Section(header: heading("iosMath")) {
                Text("The library SwiftMath is based on. MIT License.\n\nCopyright (c) 2013 MathChat")
            }
            .listRowBackground(Color.card)
            Section(header: heading("MIT License")) {
                Text(Self.mit).font(.footnote)
            }
            .listRowBackground(Color.card)
            Section(header: heading("Maths fonts")) {
                Text("Latin Modern Math, by the GUST e-foundry, under the GUST Font License, and the other maths fonts SwiftMath includes, under the SIL Open Font License. Their licences are included in the app.")
            }
            .listRowBackground(Color.card)
        }
        .foregroundStyle(Color.ink)
        .squigglyList()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}
