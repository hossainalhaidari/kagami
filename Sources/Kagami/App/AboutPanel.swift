import AppKit

/// The standard About panel, opened from the app menu.
///
/// AppKit fills in the icon, the name, the version with its build and the copyright line
/// (`NSHumanReadableCopyright`) from the bundle; only the credits under them are written here.
@MainActor
enum AboutPanel {
    static let developer = "Hossain Alhaidari"
    static let website = URL(string: "https://hossain.al/kagami/")!
    static let sourceCode = URL(string: "https://github.com/hossainalhaidari/kagami")!

    static func show() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }

    private static func credits() -> NSAttributedString {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        centred.paragraphSpacing = 6
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        func text(_ string: String, _ colour: NSColor = .labelColor) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: colour, .paragraphStyle: centred,
            ])
        }
        func link(_ title: String, _ url: URL) -> NSAttributedString {
            NSAttributedString(string: title, attributes: [
                .font: font, .link: url, .paragraphStyle: centred,
            ])
        }

        // The licences are the copies build-app.sh puts inside the bundle, so they open offline and
        // always match the version that is running. A binary run straight from .build has none,
        // and gets the repository's copy of Kagami's instead.
        func bundledLicense(_ name: String) -> URL? {
            Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Licenses")
        }
        let ownLicense = bundledLicense("Kagami") ?? sourceCode.appendingPathComponent("blob/main/LICENSE")
        let sparkleLicense = bundledLicense("Sparkle")

        var links = [link("Website", website), link("Source Code", sourceCode)]
        if let sparkleLicense {
            links.append(link("Acknowledgements", sparkleLicense))
        }

        let credits = NSMutableAttributedString()
        credits.append(text("Developed by \(developer)\n"))

        let licenseName = "MIT License"
        let licenseLine = NSMutableAttributedString(attributedString: text(
            "Free and open source under the \(licenseName).\n", .secondaryLabelColor))
        let nameRange = (licenseLine.string as NSString).range(of: licenseName)
        if nameRange.location != NSNotFound {
            licenseLine.addAttribute(.link, value: ownLicense, range: nameRange)
        }
        credits.append(licenseLine)

        for (index, link) in links.enumerated() {
            if index > 0 { credits.append(text(" · ", .tertiaryLabelColor)) }
            credits.append(link)
        }
        return credits
    }
}
