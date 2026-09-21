import SwiftUI

struct PreferenceChecklist: View {
    let section: PreferenceSection
    @Binding var profile: CookProfile
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private var selected: Set<String> { profile.selectedIDs(section) }
    private var matches: [PreferenceOption] { section.options.filter { $0.matches(query) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(section.title.lowercased())", text: $query)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityIdentifier("preference-search")
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
                }.padding(15).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 22)
                HStack {
                    Text("\(selected.count) selected")
                    Spacer()
                    if !selected.isEmpty { Button("Clear selections") { profile.select([], for: section) } }
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 14)
                List {
                    if section == .allergies {
                        Section {
                            row("No known allergies", checked: profile.allergyStatus == .noneKnown, id: "allergy-none") { profile.setNoKnownAllergies() }
                            row("Not specified", checked: profile.allergyStatus == .unspecified, id: "allergy-unspecified") { profile.select([], for: .allergies) }
                        } footer: { Text("Choose the foods you are allergic to. Dietary restrictions have their own list. These settings are controlled by you.") }
                    }
                    if !selected.isEmpty {
                        Section("Selected") {
                            ForEach(selected.sorted(), id: \.self) { id in option(id, name: section.label(id)) }
                        }
                    }
                    Section(query.isEmpty ? "Choose any that apply" : "Search results") {
                        ForEach(matches.filter { !selected.contains($0.id) }) { item in option(item.id, name: item.name) }
                        if matches.isEmpty { Text("No matches. Try another name.").foregroundStyle(.secondary) }
                    }
                }.listStyle(.insetGrouped).scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
            }.background(Theme.cream).foregroundStyle(Theme.ink).keyboardDone()
                .navigationTitle(section.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("close-preference-picker") } }
        }
    }
    private func option(_ id: String, name: String) -> some View {
        row(name, checked: selected.contains(id), id: "option-" + id) {
            var values = selected
            if !values.insert(id).inserted { values.remove(id) }
            profile.select(values, for: section)
        }
    }
    private func row(_ name: String, checked: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: checked ? "checkmark.square.fill" : "square").foregroundStyle(Theme.green).font(.title3)
                Text(name).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id).accessibilityLabel(name)
            .accessibilityValue(checked ? "Selected" : "Not selected").accessibilityAddTraits(checked ? .isSelected : [])
    }
}

struct CookingTextEntry: View {
    let title: String
    let hint: String
    let message: String
    let actionTitle: String
    var keyboard: UIKeyboardType = .default
    @Binding var text: String
    let save: () -> String?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                    TextField(hint, text: $text).keyboardType(keyboard).padding(16)
                        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("cooking-entry")
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button(actionTitle) {
                        dismissCookingKeyboard()
                        error = save()
                        if error == nil { dismiss() }
                    }.buttonStyle(FilledButton())
                }.padding(24)
            }.background(Theme.cream).keyboardDone()
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
