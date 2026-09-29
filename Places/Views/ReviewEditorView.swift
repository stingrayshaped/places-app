import SwiftUI
import SwiftData

struct ReviewEditorView: View {
    @Bindable var restaurant: Restaurant
    @State private var session = ReviewSession()
    @FocusState private var focusedID: UUID?
    @State private var undoStack: [[ReviewStatement]] = []
    @State private var busyID: UUID?       // statement currently being split or fixed
    @State private var notice: String?

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
                        .onChange(of: statement.text) { oldValue, newValue in
                            guard newValue.contains("\n") else { return }

                            if newValue.replacingOccurrences(of: "\n", with: "") == oldValue {
                                // The return key inserted a line break at the cursor: drop it.
                                statement.text = oldValue
                            } else {
                                // Pasted multi-line text: turn the breaks into spaces.
                                statement.text = newValue
                                    .replacingOccurrences(of: "\n", with: " ")
                                    .trimmingCharacters(in: .whitespaces)
                            }
                            focusedID = nil
                        }
                        .overlay {
                            // While this line isn't being edited, a plain layer covers the
                            // text field so swipes and long-presses reach the row.
                            // Tapping it focuses the field.
                            if focusedID != statement.id {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { focusedID = statement.id }
                                    .accessibilityHidden(true)
                            }
                        }

                    if busyID == statement.id {
                        ProgressView()
                    }
                }
                .contentShape(Rectangle())
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
                    if ReviewPipeline.canSplit(statement.text) {
                        Button {
                            Task { await splitFurther(statement) }
                        } label: {
                            Label("Split Further", systemImage: "scissors")
                        }
                        .disabled(busyID != nil)
                    }
                    Button {
                        Task { await fixStatement(statement) }
                    } label: {
                        Label("Fix Statement", systemImage: "wand.and.stars")
                    }
                    .disabled(busyID != nil)
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
        .alert(
            "Heads Up",
            isPresented: Binding(
                get: { notice != nil },
                set: { if !$0 { notice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
        // Tidy the line the user just finished, and snapshot before the next edit
        .onChange(of: focusedID) { oldID, newID in
            if let oldID, oldID != newID,
               let index = restaurant.statements.firstIndex(where: { $0.id == oldID }) {
                let text = restaurant.statements[index].text
                let tidy = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if tidy != text {
                    restaurant.statements[index].text = tidy
                }
            }
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

    // MARK: Split Further

    private func splitFurther(_ statement: ReviewStatement) async {
        busyID = statement.id
        defer { busyID = nil }
        let original = statement.text

        let pieces = await ReviewPipeline.splitStatement(original)
        guard let index = restaurant.statements.firstIndex(where: { $0.id == statement.id }),
              restaurant.statements[index].text == original else { return }   // edited or removed meanwhile

        guard pieces.count > 1 else {
            notice = "That statement reads as a single idea, so there was nothing to split."
            return
        }

        pushUndo()
        // The first piece keeps the original identity; the rest are new statements.
        var replacements: [ReviewStatement] = []
        for (offset, piece) in pieces.enumerated() {
            replacements.append(ReviewStatement(
                id: offset == 0 ? statement.id : UUID(),
                text: piece,
                sourceAudio: statement.sourceAudio
            ))
        }
        withAnimation {
            restaurant.statements.replaceSubrange(index...index, with: replacements)
        }
    }

    // MARK: Fix Statement

    private func fixStatement(_ statement: ReviewStatement) async {
        busyID = statement.id
        defer { busyID = nil }
        let original = statement.text

        do {
            guard let fixed = try await ReviewPipeline.fixStatement(original) else {
                notice = "That statement already reads fine."
                return
            }
            guard let index = restaurant.statements.firstIndex(where: { $0.id == statement.id }),
                  restaurant.statements[index].text == original else { return }   // edited or removed meanwhile

            pushUndo()
            withAnimation {
                restaurant.statements[index].text = fixed
            }
        } catch AnalysisError.modelUnavailable {
            notice = "Apple Intelligence isn't available on this device."
        } catch {
            print("Fix failed:", error)
            notice = "Couldn't fix that statement. Try again."
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
