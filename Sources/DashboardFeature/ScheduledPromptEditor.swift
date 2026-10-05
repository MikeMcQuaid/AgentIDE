import AgentIDEDomain
import SwiftUI
import TerminalUI

/// Familiar repeat, day and time controls beside the shared agent pickers.
struct ScheduledPromptEditor: View {
    // MARK: Lifecycle

    init(prompt: ScheduledPrompt, model: ScheduledPromptsModel, choices: @escaping (AgentKind) -> AgentChoices) {
        _prompt = State(initialValue: prompt)
        self.model = model
        self.choices = choices
    }

    // MARK: Internal

    let model: ScheduledPromptsModel
    let choices: (AgentKind) -> AgentChoices

    var body: some View {
        VStack {
            Form {
                Section("Scheduled prompt") {
                    TextField("Name", text: $prompt.name)
                        .focused($nameFocused)
                    TextField("Prompt", text: $prompt.prompt, axis: .vertical)
                        .lineLimit(Self.promptLines)
                    AgentOptionPickers(
                        agent: $prompt.agent, model: $prompt.model, effort: $prompt.effort, choices: choices,
                    )
                }
                scheduleSection
                if let error = model.error {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            buttons
        }
        .frame(width: Self.width)
        .onAppear { nameFocused = true }
    }

    // MARK: Private

    private static let width: CGFloat = 620
    private static let promptLines = 5 ... 10

    @State private var prompt: ScheduledPrompt

    @Environment(\.dismiss)
    private var dismiss
    @FocusState private var nameFocused: Bool

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: prompt.schedule.hour, minute: prompt.schedule.minute))
                    ?? Date()
            },
            set: { date in
                prompt.schedule.hour = Calendar.current.component(.hour, from: date)
                prompt.schedule.minute = Calendar.current.component(.minute, from: date)
            },
        )
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            Picker("Repeat", selection: $prompt.schedule.frequency) {
                ForEach(PromptSchedule.Frequency.allCases, id: \.self) { frequency in
                    Text(frequency.rawValue.capitalized).tag(frequency)
                }
            }
            if prompt.schedule.frequency == .weekly {
                Picker("On", selection: $prompt.schedule.weekday) {
                    ForEach(PromptSchedule.weekdays, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                }
            } else if prompt.schedule.frequency == .monthly {
                Picker("On day", selection: $prompt.schedule.day) {
                    ForEach(PromptSchedule.monthDays, id: \.self) { day in
                        Text(String(day)).tag(day)
                    }
                }
                Text("Months without this day are skipped.")
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
            DatePicker("At", selection: time, displayedComponents: .hourAndMinute)
            Text("Time zone: " + prompt.schedule.timeZoneIdentifier)
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
            Toggle("Enabled", isOn: $prompt.isEnabled)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                if model.save(prompt) {
                    dismiss()
                }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(prompt.isValid == false)
        }
        .padding([.horizontal, .bottom])
    }
}
