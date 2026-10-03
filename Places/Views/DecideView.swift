//
//  DecideView.swift
//  Places
//
//  Created by Raymond Yang on 10/2/26.
//


import SwiftUI

struct DecideView: View {
    let restaurants: [Restaurant]
    let definitions: [TagDefinition]

    @Environment(\.dismiss) private var dismiss

    @State private var steps: [ChoiceStep] = []
    @State private var showResult = false   // set by "Pick for me"

    private struct Pill: Identifiable {
        let stepID: UUID
        let text: String
        let icon: String
        var id: UUID { stepID }
    }

    private var definitionsByKey: [String: TagDefinition] {
        Dictionary(definitions.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        let current = ChoiceEngine.snapshot(restaurants: restaurants,
                                            definitions: definitions,
                                            steps: steps)

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !pills.isEmpty {
                        pillsView
                    }
                    content(for: current)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Help Me Choose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Over", action: reset)
                        .disabled(steps.isEmpty && !showResult)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar(for: current)
            }
        }
    }

    // MARK: Which screen

    @ViewBuilder
    private func content(for current: ChoiceSnapshot) -> some View {
        if restaurants.count < 2 {
            message("Not Enough Reviews Yet",
                    "Add at least two reviews, with a few tags, and this will help you choose between them.")
        } else if current.contenders.isEmpty {
            message("Nothing Matches",
                    "No place fits everything you've said. Remove a filter above, or tap Back.")
        } else if current.question == nil && steps.isEmpty {
            message("Not Enough Tags Yet",
                    "Your reviews don't have enough tags to tell them apart. Apply tags to a few of them and try again.")
        } else if showResult || current.question == nil {
            resultView(current)
        } else if let question = current.question {
            questionView(question, current)
        }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        ContentUnavailableView(title, systemImage: "questionmark.bubble", description: Text(detail))
            .frame(maxWidth: .infinity)
    }

    // MARK: Pills ("So far")

    private var pills: [Pill] {
        steps.compactMap { step -> Pill? in
            switch step.kind {
            case .answer(let key, let answer):
                guard answer != .skip, let definition = definitionsByKey[key] else { return nil }
                if answer == .want {
                    return Pill(stepID: step.id, text: definition.name, icon: "tag")
                }
                let prefix = definition.kind == .warning ? "Without" : "Not"
                return Pill(stepID: step.id, text: "\(prefix) \(definition.name)", icon: "nosign")
            case .notThisOne(let id):
                guard let restaurant = restaurants.first(where: { $0.id == id }) else { return nil }
                return Pill(stepID: step.id, text: "Not \(restaurant.name)", icon: "xmark.circle")
            }
        }
    }

    private var pillsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("So far")
                .font(.footnote)
                .foregroundStyle(.secondary)

            FlowLayout {
                ForEach(pills) { pill in
                    Button {
                        steps.removeAll { $0.id == pill.stepID }
                        showResult = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: pill.icon)
                            Text(pill.text)
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .font(.subheadline)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: A question

    private func title(for question: ChoiceQuestion) -> String {
        if question.kind == .warning {
            return "Would “\(question.name)” be a deal-breaker?"
        }
        switch question.section {
        case "Cuisine": return "In the mood for \(question.name) food?"
        case "Type": return "Are you after \(question.name)?"
        case "Price": return "Is \(question.name) the right price range?"
        default: return "Do you want “\(question.name)”?"
        }
    }

    private func questionView(_ question: ChoiceQuestion, _ current: ChoiceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Question \(current.answered + 1) of \(ChoiceEngine.maxQuestions) · \(current.contenders.count) places in the running")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(title(for: question))
                .font(.title2.bold())

            if !question.definition.isEmpty {
                Text(question.definition)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                if question.kind == .warning {
                    answerButton("Deal-breaker", question, .avoid, prominent: true)
                    answerButton("That's fine", question, .skip)
                } else {
                    answerButton("Yes", question, .want, prominent: true)
                    answerButton("No", question, .avoid)
                    answerButton("Doesn't matter", question, .skip)
                }
            }
        }
    }

    @ViewBuilder
    private func answerButton(_ label: String,
                              _ question: ChoiceQuestion,
                              _ answer: ChoiceAnswer,
                              prominent: Bool = false) -> some View {
        let button = Button {
            steps.append(ChoiceStep(kind: .answer(key: question.key, answer: answer)))
        } label: {
            Text(label)
                .frame(maxWidth: .infinity)
        }

        if prominent {
            button.buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            button.buttonStyle(.bordered).controlSize(.large)
        }
    }

    // MARK: The result

    private func authorName(_ restaurant: Restaurant) -> String {
        let name = restaurant.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "a friend" : name
    }

    /// The tags you said yes to that this place has, or its own top tags if none were chosen.
    private func reasons(for restaurant: Restaurant, wanted: [String]) -> [String] {
        let keys = Set(restaurant.appliedTags.map(\.tagKey))
        let matching = wanted
            .filter { keys.contains($0) }
            .compactMap { definitionsByKey[$0]?.name }
        if !matching.isEmpty { return matching }
        return restaurant.appliedDefinitions(.tag, in: definitions).prefix(4).map(\.name)
    }

    /// Statements that back up the matching tags, or the first few if there are none.
    private func supportingStatements(for restaurant: Restaurant, wanted: [String]) -> [ReviewStatement] {
        var ids = Set<UUID>()
        for application in restaurant.appliedTags where wanted.contains(application.tagKey) {
            ids.formUnion(application.evidence)
        }
        var picked = restaurant.statements.filter { ids.contains($0.id) }
        if picked.isEmpty { picked = restaurant.statements }
        return Array(picked.prefix(3))
    }

    private func resultView(_ current: ChoiceSnapshot) -> some View {
        let best = current.contenders[0]
        let others = Array(current.contenders.dropFirst().prefix(2))
        let why = reasons(for: best, wanted: current.wanted)
        let statements = supportingStatements(for: best, wanted: current.wanted)

        return VStack(alignment: .leading, spacing: 16) {
            Text("How about…")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(best.name)
                    .font(.largeTitle.bold())
                if !best.isMine {
                    Label("Recommended by \(authorName(best))", systemImage: "person.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !best.address.isEmpty {
                    Text(best.address)
                        .foregroundStyle(.secondary)
                }
            }

            if !why.isEmpty {
                FlowLayout {
                    ForEach(why, id: \.self) { name in
                        TagChip(text: name)
                    }
                }
            }

            if !best.summary.isEmpty {
                Text(best.summary)
            }

            if !statements.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(statements) { statement in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(statement.text)
                        }
                    }
                }
            }

            VStack(spacing: 10) {
                if !best.address.isEmpty {
                    Menu {
                        Button("Driving", systemImage: "car.fill") {
                            MapsLauncher.openDirections(to: best, mode: .driving)
                        }
                        Button("Walking", systemImage: "figure.walk") {
                            MapsLauncher.openDirections(to: best, mode: .walking)
                        }
                        Button("Transit", systemImage: "tram.fill") {
                            MapsLauncher.openDirections(to: best, mode: .transit)
                        }
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .frame(maxWidth: .infinity)
                    } primaryAction: {
                        MapsLauncher.openDirections(to: best, mode: .driving)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button {
                    steps.append(ChoiceStep(kind: .notThisOne(best.id)))
                } label: {
                    Label("Not this one", systemImage: "hand.thumbsdown")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if showResult && current.question != nil {
                    Button {
                        showResult = false
                    } label: {
                        Label("Keep narrowing", systemImage: "arrow.uturn.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Also in the running")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(others) { other in
                        Text(other.isMine
                             ? other.name
                             : "\(other.name) · recommended by \(authorName(other))")
                    }
                }
            }
        }
    }

    // MARK: Bottom bar and actions

    private func bottomBar(for current: ChoiceSnapshot) -> some View {
        HStack {
            Button(action: undo) {
                Label("Back", systemImage: "arrow.uturn.backward")
            }
            .disabled(steps.isEmpty && !showResult)

            Spacer()

            if !showResult && current.question != nil && !current.contenders.isEmpty {
                Button {
                    showResult = true
                } label: {
                    Label("Pick for me", systemImage: "wand.and.stars")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func undo() {
        if showResult {
            showResult = false
        } else if !steps.isEmpty {
            steps.removeLast()
        }
    }

    private func reset() {
        steps = []
        showResult = false
    }
}
