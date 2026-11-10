import SwiftUI
import UniformTypeIdentifiers

/// Tab root hosting PosterBoard and the Phone passcode theme swap behind one
/// picker, the same "master picker, no sub-options" pattern as Siri AI Setup.
struct CustomizationView: View {
    @State private var mode: Mode = .posterBoard

    enum Mode: String, CaseIterable, Identifiable {
        case posterBoard = "PosterBoard"
        case passcode = "Passcode"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $mode) {
                    ForEach(Mode.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
                switch mode {
                case .posterBoard: PosterBoardView()
                case .passcode: PasscodeThemeView()
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Customization")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct PasscodeThemeView: View {
    @AppStorage("phoneHash") private var phoneHash = ""
    @State private var showPackageImporter = false
    @State private var isBusy = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showAppliedAlert = false
    @State private var appliedCount = 0
    @State private var showRestoreConfirm = false
    @State private var busyMessage = "Applying theme"
    @State private var extractedZipURL: URL?

    private let passthmType = UTType(filenameExtension: "passthm", conformingTo: .data)!

    var body: some View {
        ZStack {
            if BadQuery.isAvailable {
                content
            } else {
                locked
            }
            if isBusy { ProgressOverlay(message: busyMessage) }
        }
        .fileImporter(
            isPresented: $showPackageImporter,
            allowedContentTypes: [passthmType, .zip],
            onCompletion: importPackage
        )
        .confirmationDialog("Restore original theme?", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("Restore", role: .destructive, action: restoreOriginal)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replaces the current dialer theme with the one saved before your first change.")
        }
        .alert("Something went wrong", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .alert("Applied", isPresented: $showAppliedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Replaced \(appliedCount) image\(appliedCount == 1 ? "" : "s"). Restart the Phone app to see the changes.")
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 12)
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Phone app's dialer theming")
                        .font(.title2.weight(.semibold))
                    Text("Swap the Phone app's dialer keypad (0–9) images using a .passthm or .zip package. Every localized copy of a given image is replaced, not just one language.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button { showPackageImporter = true } label: {
                    Label("Choose package", systemImage: "square.and.arrow.down")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .glassAction(prominent: true)
                .tint(Theme.accent)
                .disabled(isBusy)
                HStack(spacing: 20) {
                    Button("Extract images", systemImage: "square.and.arrow.up", action: extractImages)
                        .foregroundStyle(Theme.accent)
                        .disabled(isBusy)
                    if PasscodeThemeManager.shared.hasBackup {
                        Button("Restore original theme", role: .destructive) { showRestoreConfirm = true }
                            .disabled(isBusy)
                    }
                }
                .font(.subheadline.weight(.semibold))
                if let extractedZipURL {
                    ShareLink(item: extractedZipURL) {
                        Label("Share extracted images", systemImage: "square.and.arrow.up.on.square")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                Text("No respring is needed — just relaunch the Phone app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.pagePadding)
        }
        .scrollIndicators(.hidden)
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Image(systemName: "lock")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("Theming unavailable")
                .font(.title2.weight(.semibold))
            Text("This iOS version cannot open the Phone app's container through bad_query, so its dialer theme cannot be changed here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(Theme.pagePadding)
    }

    private func importPackage(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            apply(from: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    private func apply(from url: URL) {
        guard !isBusy else { return }
        isBusy = true
        busyMessage = "Applying theme"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var hash = phoneHash
                if hash.isEmpty {
                    hash = try BadQuery.findMobilePhoneHash()
                    DispatchQueue.main.async { phoneHash = hash }
                }
                let count = try PasscodeThemeManager.shared.applyTheme(from: url, appHash: hash)
                DispatchQueue.main.async {
                    isBusy = false
                    appliedCount = count
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showAppliedAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    isBusy = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }

    private func restoreOriginal() {
        guard !isBusy else { return }
        isBusy = true
        busyMessage = "Restoring theme"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var hash = phoneHash
                if hash.isEmpty {
                    hash = try BadQuery.findMobilePhoneHash()
                    DispatchQueue.main.async { phoneHash = hash }
                }
                try PasscodeThemeManager.shared.restoreOriginal(appHash: hash)
                DispatchQueue.main.async {
                    isBusy = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    isBusy = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }

    private func extractImages() {
        guard !isBusy else { return }
        isBusy = true
        busyMessage = "Extracting images"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var hash = phoneHash
                if hash.isEmpty {
                    hash = try BadQuery.findMobilePhoneHash()
                    DispatchQueue.main.async { phoneHash = hash }
                }
                let url = try PasscodeThemeManager.shared.extractImages(appHash: hash)
                DispatchQueue.main.async {
                    isBusy = false
                    extractedZipURL = url
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    isBusy = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}
