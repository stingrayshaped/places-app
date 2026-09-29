import SwiftUI
import SwiftData

struct ReviewEditorView: View {
    @Bindable var restaurant: Restaurant
    @State private var session = ReviewSession()
    @FocusState private var focusedID: UUID?
    @State private var undoStack: [[ReviewStatement]] = []

    var body: some View {
        List {
            ForEach($restaurant.statements) { $statement in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(lineNumber(for: statement))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)

                    TextField("Statement", text: $statement.text, axis: .vertical)
                        .focused($focusedID, equals: statement.id)
                        .submitLabel(.done)
                        .onSubmit { focusedID = nil }
                        .onChange(of: statement.text) { _, newValue in
                            if newValue.contains("\n") {
                                statement.text = newValue
                                    .replacingOccurrences(of: "\n", with: " ")
                                    .trimmingCharacters(in: .whitespaces)
                                focusedID = nil
                            }
                        }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !isFirst(statement) {
                        Button {
                            mergeWithPrevious(statement)
                        } label: {
                            Label("Merge Up", systemImage: "arrow.triangle.merge")
                        }
                        .tint(.blue)
                    }
                }
                .contextMenu {
                    if !isFirst(statement) {
                        Button {
                            mergeWithPrevious(statement)
                        } label: {
                            Label("Merge with Above", systemImage: "arrow.up.to.line")
                        }
                    }
                }
            }
            .onDelete { offsets in
                pushUndo()
                restaurant.statements.remove(atOffsets: offsets)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .overlay {
            if restaurant.statements.isEmpty && session.stage == .idle {
                ContentUnavailableView(
                    "No Statements Yet",
                    systemImage: "mic",
                    description: Text("Tap the record button and say a few things about this restaurant.")
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsRecordBar {
                recordBar
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: showsRecordBar)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                    .disabled(!canUndo)
            }
        }
        // Snapshot before the user starts editing a line
        .onChange(of: focusedID) { _, newID in
            if newID != nil { pushUndo() }
        }
        // Snapshot before a new recording's statements get appended
        .onChange(of: session.stage) { _, newStage in
            if newStage == .transcribing { pushUndo() }
        }
        .onDisappear {
            session.discardIfRecording()
            Task { await AnalysisCenter.shared.refresh(restaurant) }
        }
    }

    // MARK: Line numbers

    private func lineNumber(for statement: ReviewStatement) -> Int {
        (restaurant.statements.firstIndex { $0.id == statement.id } ?? 0) + 1
    }

    private func isFirst(_ statement: ReviewStatement) -> Bool {
        restaurant.statements.first?.id == statement.id
    }

    // MARK: Merging

    /// Appends this statement's text to the one above it, then removes it.
    private func mergeWithPrevious(_ statement: ReviewStatement) {
        guard let index = restaurant.statements.firstIndex(where: { $0.id == statement.id }),
              index > 0 else { return }

        pushUndo()
        let combined = restaurant.statements[index - 1].text + " " + restaurant.statements[index].text
        withAnimation {
            restaurant.statements[index - 1].text = combined.trimmingCharacters(in: .whitespaces)
            restaurant.statements.remove(at: index)
        }
    }

    // MARK: Undo

    private var canUndo: Bool {
        session.stage == .idle && undoStack.contains { $0 != restaurant.statements }
    }

    private func pushUndo() {
        undoStack.append(restaurant.statements)
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    private func undo() {
        focusedID = nil
        // Skip any snapshots identical to what's on screen
        while let previous = undoStack.popLast() {
            if previous != restaurant.statements {
                withAnimation { restaurant.statements = previous }
                break
            }
        }
    }

    // MARK: Bottom bar

    /// Hidden while editing a line, unless a recording is in progress
    /// (so the stop button is never lost).
    private var showsRecordBar: Bool {
        focusedID == nil || session.isRecording
    }

    private var recordBar: some View {
        VStack(spacing: 8) {
            if let message = session.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                if session.pendingFileName != nil {
                    Button("Try Again") {
                        Task { await session.retry(for: restaurant) }
                    }
                    .font(.footnote)
                }
            }

            HStack(spacing: 8) {
                if session.isBusy { ProgressView() }
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await session.toggleRecording(for: restaurant) }
            } label: {
                ZStack {
                    Circle()
                        .stroke(.secondary, lineWidth: 4)
                        .frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: session.isRecording ? 8 : 30)
                        .fill(.red)
                        .frame(width: session.isRecording ? 28 : 60,
                               height: session.isRecording ? 28 : 60)
                }
                .animation(.snappy, value: session.isRecording)
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)
            .opacity(session.isBusy ? 0.4 : 1)
            .accessibilityLabel(session.isRecording ? "Stop recording" : "Record")
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var statusText: String {
        switch session.stage {
        case .idle:
            restaurant.statements.isEmpty ? "Tap to record" : "Tap to record more"
        case .recording: "Recording… tap to stop"
        case .transcribing: "Transcribing…"
        case .segmenting: "Finding statement breaks…"
        }
    }
}
