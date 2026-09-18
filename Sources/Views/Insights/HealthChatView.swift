import SwiftUI
import PhotosUI
import UIKit

struct HealthChatView: View {
    @EnvironmentObject var healthKit: HealthKitManager
    @EnvironmentObject var bluetooth: BandBluetoothManager
    @EnvironmentObject var coordinator: ActivitySyncCoordinator
    @EnvironmentObject var scaleLog: ScaleLogStore
    @AppStorage("aiInsightsEnabled") private var isEnabled = false
    @AppStorage("aiProvider") private var provider: AIProvider = .claude
    @State private var viewModel: HealthChatViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if !isEnabled {
                    disabledState
                } else if let viewModel {
                    ChatContentView(viewModel: viewModel, providerLabel: provider.label)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("AI Insights")
            .toolbar {
                if isEnabled, let viewModel {
                    ToolbarItem(placement: .primaryAction) {
                        // Forces the keyboard down before leaving — a
                        // focused TextField can otherwise leave the
                        // keyboard visually stuck on top of whatever's
                        // navigated to next, swallowing every touch (see
                        // RootView's tab-change fix, which covers tab
                        // switches; this covers manually leaving here).
                        Button("Exit Chat") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            viewModel.clear()
                        }
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = HealthChatViewModel(healthKit: healthKit, bluetooth: bluetooth, coordinator: coordinator, scaleLog: scaleLog)
            }
        }
    }

    private var disabledState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("AI Insights is off")
                .font(.headline)
            Text("Turn this on in Settings → AI Insights. Once enabled, sending a message here (with an optional photo) sends a text summary of your Health data to \(provider.label) through your own relay server — nothing is sent automatically or in the background.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ChatContentView: View {
    @ObservedObject var viewModel: HealthChatViewModel
    let providerLabel: String
    @State private var photoPickerItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if viewModel.messages.isEmpty {
                            Text("Ask about your recent activity, heart rate, or trends. \(providerLabel) only sees a text summary of your Health data, not raw records — and it's not a medical professional, so don't treat its answers as medical advice.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        if viewModel.isSending {
                            HStack {
                                ProgressView()
                                Text("Thinking…").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .onChange(of: viewModel.messages) { _, newValue in
                    guard let last = newValue.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            if let pendingImageData = viewModel.pendingImageData, let uiImage = UIImage(data: pendingImageData) {
                HStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Photo attached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        viewModel.pendingImageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            HStack {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                }
                TextField("Ask about your health data…", text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { viewModel.send() }
                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(
                    (viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.pendingImageData == nil)
                        || viewModel.isSending
                )
            }
            .padding()
        }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let resized = ImageResizer.resizedJPEGData(from: image) {
                    viewModel.pendingImageData = resized
                }
                photoPickerItem = nil
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if !message.content.isEmpty {
                    Text(message.content)
                }
            }
            .padding(10)
            .background(
                message.role == .user ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }
}
