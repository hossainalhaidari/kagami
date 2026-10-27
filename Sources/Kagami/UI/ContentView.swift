import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: FlashModel
    @State private var isChoosingImage = false
    @State private var isConfirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            imageRow
            driveRow
            Divider()
            actionArea
        }
        .padding(24)
        .frame(width: 520)
        .fileImporter(isPresented: $isChoosingImage, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { model.selectImage(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !model.isWorking else { return false }
            model.selectImage(url)
            return true
        }
        .confirmationDialog(confirmationTitle, isPresented: $isConfirming) {
            Button("Erase and Flash", role: .destructive) { model.flash() }
        } message: {
            Text("All data on this drive will be permanently erased.")
        }
    }

    // MARK: - Step 1: image

    private var imageRow: some View {
        StepRow(number: 1, title: "Image") {
            HStack {
                if let url = model.imageURL, let info = model.imageInfo {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text(imageSummary(info))
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                } else {
                    Text("No image selected").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…") { isChoosingImage = true }
                    .disabled(model.isWorking)
            }
            if let error = model.imageError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Step 2: drive

    private var driveRow: some View {
        StepRow(number: 2, title: "Drive") {
            if model.drives.isEmpty {
                Text("Insert a USB drive or SD card")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Drive", selection: $model.selectedDriveID) {
                    Text("Select a drive").tag(Drive.ID?.none)
                    ForEach(model.drives) { drive in
                        Text("\(drive.name) — \(drive.formattedSize) (\(drive.bsdName))")
                            .tag(Drive.ID?.some(drive.id))
                    }
                }
                .labelsHidden()
                .disabled(model.isWorking)
            }
        }
    }

    // MARK: - Step 3: flash / progress

    @ViewBuilder
    private var actionArea: some View {
        switch model.state {
        case .idle:
            VStack(spacing: 8) {
                Button {
                    isConfirming = true
                } label: {
                    Text("Flash").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canFlash)

                if let blocker = model.blocker {
                    Text(blocker).font(.caption).foregroundStyle(.red)
                }
            }

        case .busy(let message):
            progressView(title: message, fraction: nil)

        case let .running(phase, fraction):
            progressView(
                title: "\(phase == .writing ? "Writing" : "Verifying")… \(Int(fraction * 100))%",
                fraction: fraction
            )

        case .finished(verified: true):
            resultView(symbol: "checkmark.circle.fill", color: .green, title: "Flash complete")

        case .finished(verified: false):
            resultView(symbol: "exclamationmark.triangle.fill", color: .orange, title: "Written, not verified")

        case .failed(let message):
            resultView(symbol: "xmark.octagon.fill", color: .red, title: message)
        }
    }

    private func progressView(title: String, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).monospacedDigit()
                Spacer()
                Text(model.statusDetail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Spacer()
                if model.isVerifying {
                    Button("Skip Verification") { model.skipVerification() }
                } else {
                    Button("Cancel", role: .cancel) { model.cancel() }
                }
            }
        }
    }

    private func resultView(symbol: String, color: Color, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title).fontWeight(.medium)
            } icon: {
                Image(systemName: symbol).foregroundStyle(color)
            }
            if !model.statusDetail.isEmpty {
                Text(model.statusDetail).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Done") { model.reset() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    /// "8 GB", "xz · 1.2 GB → 8 GB" or "gzip · 1.2 GB compressed".
    private func imageSummary(_ info: ImageInfo) -> String {
        let format = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        guard info.format != .raw else { return format(info.fileSize) }
        var parts = [info.format.displayName]
        if let entry = info.entryName { parts.append((entry as NSString).lastPathComponent) }
        if let size = info.imageSize {
            parts.append("\(format(info.fileSize)) → \(format(size))")
        } else {
            parts.append("\(format(info.fileSize)) compressed")
        }
        return parts.joined(separator: " · ")
    }

    private var confirmationTitle: String {
        guard let drive = model.selectedDrive else { return "" }
        return "Erase “\(drive.name)” (\(drive.formattedSize), \(drive.bsdName))?"
    }
}

private struct StepRow<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.tint))
            Text(title)
                .fontWeight(.medium)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) { content }
        }
    }
}
