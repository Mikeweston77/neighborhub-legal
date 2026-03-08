import SwiftUI
import FirebaseAuth

// MARK: - Form Builder View (Admin Only)
struct NewsletterFormBuilderView: View {
    @Binding var newsletter: Newsletter
    @Environment(\.dismiss) private var dismiss
    @State private var formFields: [NewsletterFormField]
    @State private var showAddFieldSheet = false
    @State private var editingField: NewsletterFormField?
    
    init(newsletter: Binding<Newsletter>) {
        self._newsletter = newsletter
        self._formFields = State(initialValue: newsletter.wrappedValue.formFields)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if formFields.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text.fill.badge.plus")
                            .font(.system(size: 64))
                            .foregroundColor(.gray.opacity(0.4))
                        Text("No form fields yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Add fields to create a fillable form for this newsletter")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button(action: { showAddFieldSheet = true }) {
                            Label("Add First Field", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.accentColor)
                                .cornerRadius(12)
                        }
                    }
                } else {
                    List {
                        ForEach(formFields) { field in
                            FormFieldRow(field: field, onEdit: {
                                editingField = field
                            }, onDelete: {
                                if let index = formFields.firstIndex(where: { $0.id == field.id }) {
                                    formFields.remove(at: index)
                                }
                            })
                        }
                        .onMove { from, to in
                            formFields.move(fromOffsets: from, toOffset: to)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Form Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if !formFields.isEmpty {
                            EditButton()
                        }
                        Button(action: { showAddFieldSheet = true }) {
                            Image(systemName: "plus")
                        }
                    }
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Button("Save Form") {
                        newsletter.formFields = formFields
                        newsletter.isFormEnabled = !formFields.isEmpty
                        dismiss()
                    }
                    .disabled(formFields.isEmpty)
                }
            }
            .sheet(isPresented: $showAddFieldSheet) {
                FormFieldEditorView(field: nil, onSave: { newField in
                    formFields.append(newField)
                })
            }
            .sheet(item: $editingField) { field in
                FormFieldEditorView(field: field, onSave: { updatedField in
                    if let index = formFields.firstIndex(where: { $0.id == field.id }) {
                        formFields[index] = updatedField
                    }
                })
            }
        }
    }
}

// MARK: - Form Field Row
struct FormFieldRow: View {
    let field: NewsletterFormField
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: field.fieldType.icon)
                        .foregroundColor(.accentColor)
                    Text(field.label)
                        .font(.headline)
                    if field.isRequired {
                        Text("*")
                            .foregroundColor(.red)
                            .font(.headline)
                    }
                }
                Text(field.fieldType.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !field.helpText.isEmpty {
                    Text(field.helpText)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Form Field Editor
struct FormFieldEditorView: View {
    let field: NewsletterFormField?
    let onSave: (NewsletterFormField) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var label: String
    @State private var fieldType: NewsletterFormFieldType
    @State private var isRequired: Bool
    @State private var placeholder: String
    @State private var options: [String]
    @State private var helpText: String
    @State private var newOption: String = ""
    
    init(field: NewsletterFormField?, onSave: @escaping (NewsletterFormField) -> Void) {
        self.field = field
        self.onSave = onSave
        self._label = State(initialValue: field?.label ?? "")
        self._fieldType = State(initialValue: field?.fieldType ?? .shortText)
        self._isRequired = State(initialValue: field?.isRequired ?? false)
        self._placeholder = State(initialValue: field?.placeholder ?? "")
        self._options = State(initialValue: field?.options ?? [])
        self._helpText = State(initialValue: field?.helpText ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Field Details") {
                    TextField("Label", text: $label)
                    TextField("Placeholder", text: $placeholder)
                    TextField("Help Text (optional)", text: $helpText)
                }
                
                Section("Field Type") {
                    Picker("Type", selection: $fieldType) {
                        ForEach(NewsletterFormFieldType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.rawValue)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section {
                    Toggle("Required Field", isOn: $isRequired)
                }
                
                if fieldType == .multipleChoice {
                    Section {
                        ForEach(options.indices, id: \.self) { index in
                            HStack {
                                TextField("Option \(index + 1)", text: $options[index])
                                Button(action: {
                                    options.remove(at: index)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        HStack {
                            TextField("Add new option", text: $newOption)
                            Button(action: {
                                if !newOption.isEmpty && options.count < 10 {
                                    options.append(newOption)
                                    newOption = ""
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(options.count >= 10 ? .gray : .green)
                            }
                            .disabled(newOption.isEmpty || options.count >= 10)
                        }
                    } header: {
                        Text("Options (\(options.count)/10)")
                    } footer: {
                        if options.count < 2 {
                            Text("Add at least 2 options for multiple choice")
                                .foregroundColor(.red)
                        } else if options.count >= 10 {
                            Text("Maximum of 10 options reached")
                                .foregroundColor(.orange)
                        } else {
                            Text("Add up to \(10 - options.count) more option\(10 - options.count == 1 ? "" : "s")")
                        }
                    }
                }
            }
            .navigationTitle(field == nil ? "Add Field" : "Edit Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let newField = NewsletterFormField(
                            id: field?.id ?? UUID(),
                            label: label,
                            fieldType: fieldType,
                            isRequired: isRequired,
                            placeholder: placeholder,
                            options: fieldType == .multipleChoice ? options : [],
                            helpText: helpText
                        )
                        onSave(newField)
                        dismiss()
                    }
                    .disabled(label.isEmpty || (fieldType == .multipleChoice && options.count < 2))
                }
            }
        }
    }
}

// MARK: - User Form Submission View
struct NewsletterFormSubmissionView: View {
    let newsletter: Newsletter
    @ObservedObject var submissionManager: NewsletterFormSubmissionManager
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("userName") private var userName: String = ""
    @AppStorage("userSurname") private var userSurname: String = ""
    @AppStorage("userEmail") private var userEmail: String = ""
    @State private var responses: [UUID: String] = [:]
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    @State private var selectedDate: [UUID: Date] = [:]
    @State private var checkboxStates: [UUID: Bool] = [:]
    @State private var multipleChoiceStates: [String: Bool] = [:] // For tracking multiple selections
    
    // Check if user already submitted
    private var hasAlreadySubmitted: Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return submissionManager.submissions.contains { 
            $0.newsletterId == newsletter.id && $0.submitterId == uid
        }
    }
    
    var body: some View {
        NavigationView {
            if hasAlreadySubmitted {
                // Show already submitted message
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.green)
                    
                    Text("Form Already Submitted")
                        .font(.title2)
                        .bold()
                    
                    Text("You have already submitted this form. Each user can only submit once.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .navigationTitle("Form Submission")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") { dismiss() }
                    }
                }
            } else {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(newsletter.title)
                            .font(.title2)
                            .bold()
                        Text(newsletter.summary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Your Information") {
                    Text("\(userName) \(userSurname)")
                        .font(.body)
                    if !userEmail.isEmpty {
                        Text(userEmail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                ForEach(newsletter.formFields) { field in
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(field.label)
                                    .font(.headline)
                                if field.isRequired {
                                    Text("*")
                                        .foregroundColor(.red)
                                }
                            }
                            
                            if !field.helpText.isEmpty {
                                Text(field.helpText)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            // Render appropriate input based on field type
                            switch field.fieldType {
                            case .shortText, .email, .phone:
                                TextField(field.placeholder, text: Binding(
                                    get: { responses[field.id] ?? "" },
                                    set: { responses[field.id] = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(field.fieldType == .email ? .emailAddress : field.fieldType == .phone ? .phonePad : .default)
                                
                            case .number:
                                TextField(field.placeholder, text: Binding(
                                    get: { responses[field.id] ?? "" },
                                    set: { responses[field.id] = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                
                            case .longText:
                                TextEditor(text: Binding(
                                    get: { responses[field.id] ?? "" },
                                    set: { responses[field.id] = $0 }
                                ))
                                .frame(minHeight: 100)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                
                            case .multipleChoice:
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(field.options, id: \.self) { option in
                                        Toggle(isOn: Binding(
                                            get: {
                                                let key = "\(field.id.uuidString)_\(option)"
                                                return multipleChoiceStates[key] ?? false
                                            },
                                            set: { newValue in
                                                let key = "\(field.id.uuidString)_\(option)"
                                                multipleChoiceStates[key] = newValue
                                                // Store all selected options as comma-separated string
                                                let selectedOptions = field.options.filter { opt in
                                                    let optKey = "\(field.id.uuidString)_\(opt)"
                                                    return multipleChoiceStates[optKey] ?? false
                                                }
                                                responses[field.id] = selectedOptions.isEmpty ? "" : selectedOptions.joined(separator: ", ")
                                            }
                                        )) {
                                            Text(option)
                                                .font(.body)
                                        }
                                        .toggleStyle(CheckboxToggleStyle())
                                    }
                                }
                                .padding(.vertical, 4)
                                
                            case .date:
                                DatePicker("", selection: Binding(
                                    get: { selectedDate[field.id] ?? Date() },
                                    set: { 
                                        selectedDate[field.id] = $0
                                        let formatter = DateFormatter()
                                        formatter.dateStyle = .medium
                                        responses[field.id] = formatter.string(from: $0)
                                    }
                                ), displayedComponents: .date)
                                .datePickerStyle(.compact)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fill Form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Submit") {
                        submitForm()
                    }
                }
            }
            .alert("Validation Error", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            }
        }
    }
    
    private func submitForm() {
        // Validate required fields
        for field in newsletter.formFields where field.isRequired {
            let response = responses[field.id] ?? ""
            if response.isEmpty {
                validationMessage = "Please fill in the required field: \(field.label)"
                showValidationAlert = true
                return
            }
        }
        
        // Get current user UID
        guard let uid = Auth.auth().currentUser?.uid else {
            validationMessage = "Unable to identify user. Please ensure you are signed in."
            showValidationAlert = true
            return
        }
        
        // Create submission
        let submission = NewsletterFormSubmission(
            newsletterId: newsletter.id,
            submitterId: uid,
            submitterName: "\(userName) \(userSurname)",
            submitterEmail: userEmail.isEmpty ? "\(userName.lowercased())@neighborhub.app" : userEmail,
            responses: responses,
            allowPublicSubmissionView: newsletter.allowPublicSubmissionView
        )
        
        submissionManager.submitForm(submission, newsletter: newsletter)
        dismiss()
    }
}

// MARK: - Admin Submissions View
struct NewsletterSubmissionsView: View {
    let newsletter: Newsletter
    @ObservedObject var submissionManager: NewsletterFormSubmissionManager
    let isAdmin: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubmission: NewsletterFormSubmission?
    @State private var showSummaryAnalytics = false
    
    var submissions: [NewsletterFormSubmission] {
        submissionManager.submissions.filter { $0.newsletterId == newsletter.id }
    }
    
    var body: some View {
        NavigationView {
            List {
                if submissions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.4))
                        Text("No submissions yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    ForEach(submissions) { submission in
                        Button(action: {
                            selectedSubmission = submission
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(submission.submitterName)
                                    .font(.headline)
                                Text(submission.submitterEmail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(submission.submissionDate, style: .relative)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle("Form Submissions (\(submissions.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !submissions.isEmpty {
                        Button(action: { showSummaryAnalytics = true }) {
                            Image(systemName: "chart.bar.fill")
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedSubmission) { submission in
                SubmissionDetailView(
                    submission: submission,
                    newsletter: newsletter,
                    submissionManager: submissionManager,
                    isAdmin: isAdmin
                )
            }
            .sheet(isPresented: $showSummaryAnalytics) {
                FormSummaryAnalyticsView(
                    newsletter: newsletter,
                    submissionManager: submissionManager
                )
            }
        }
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: NewsletterFormSubmission.SubmissionStatus
    
    var body: some View {
        Text(status.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(8)
    }
    
    var backgroundColor: Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}

// MARK: - Submission Detail View
struct SubmissionDetailView: View {
    let submission: NewsletterFormSubmission
    let newsletter: Newsletter
    @ObservedObject var submissionManager: NewsletterFormSubmissionManager
    let isAdmin: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Submitter") {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(submission.submitterName)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(submission.submitterEmail)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Submitted")
                        Spacer()
                        Text(submission.submissionDate, style: .date)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Responses") {
                    ForEach(newsletter.formFields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label)
                                .font(.headline)
                            if let response = submission.responses[field.id] {
                                Text(response)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No response")
                                    .font(.body)
                                    .italic()
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Submission Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Form Submission Manager
class NewsletterFormSubmissionManager: ObservableObject {
    @Published var submissions: [NewsletterFormSubmission] = []
    @AppStorage("newsletterSubmissions") private var submissionsData: String = ""
    
    private var usingFirestore: Bool = false
    
    init() {
        #if canImport(FirebaseFirestore)
            usingFirestore = true
            FirebaseManager.shared.watchNewsletterSubmissions { [weak self] items in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // Merge: Keep locally-added submissions that aren't in Firestore yet
                    let firestoreIds = Set(items.map { $0.id })
                    let localOnly = self.submissions.filter { !firestoreIds.contains($0.id) }
                    // Combine Firestore submissions with local-only ones
                    self.submissions = (items + localOnly).sorted { $0.submissionDate > $1.submissionDate }
                }
            }
        #else
            loadSubmissions()
        #endif
    }
    
    deinit {
        #if canImport(FirebaseFirestore)
            FirebaseManager.shared.stopWatchingNewsletterSubmissions()
        #endif
    }
    
    func submitForm(_ submission: NewsletterFormSubmission, newsletter: Newsletter) {
        // Always add locally first for immediate UI update
        submissions.insert(submission, at: 0)
        
        if usingFirestore {
            FirebaseManager.shared.createOrUpdateNewsletterSubmission(submission, newsletter: newsletter) { [weak self] err in
                if let err = err {
                    print("Failed to submit form: \(err)")
                    // Remove the local submission if Firestore write failed
                    DispatchQueue.main.async {
                        self?.submissions.removeAll { $0.id == submission.id }
                    }
                }
                // Note: Firestore listener will eventually update with the saved submission
            }
        } else {
            saveSubmissions()
        }
    }
    
    func updateSubmissionStatus(_ id: UUID, status: NewsletterFormSubmission.SubmissionStatus) {
        if let index = submissions.firstIndex(where: { $0.id == id }) {
            submissions[index].status = status
            
            if usingFirestore {
                FirebaseManager.shared.createOrUpdateNewsletterSubmission(submissions[index]) { err in
                    if let err = err {
                        print("Failed to update submission status: \(err)")
                    }
                }
            } else {
                saveSubmissions()
            }
        }
    }
    
    func deleteSubmission(_ id: UUID) {
        submissions.removeAll { $0.id == id }
        
        if usingFirestore {
            FirebaseManager.shared.deleteNewsletterSubmission(id: id.uuidString) { err in
                if let err = err {
                    print("Failed to delete submission: \(err)")
                }
            }
        } else {
            saveSubmissions()
        }
    }
    
    private func loadSubmissions() {
        guard let data = submissionsData.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([NewsletterFormSubmission].self, from: data)
        else {
            submissions = []
            return
        }
        submissions = decoded
    }
    
    private func saveSubmissions() {
        guard !usingFirestore,
              let encoded = try? JSONEncoder().encode(submissions),
              let string = String(data: encoded, encoding: .utf8)
        else { return }
        submissionsData = string
    }
}

// MARK: - Form Summary Analytics View
struct FormSummaryAnalyticsView: View {
    let newsletter: Newsletter
    @ObservedObject var submissionManager: NewsletterFormSubmissionManager
    @Environment(\.dismiss) private var dismiss
    
    var submissions: [NewsletterFormSubmission] {
        submissionManager.submissions.filter { $0.newsletterId == newsletter.id }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Overall Statistics
                    overallStatsSection
                    
                    // Combined Responses View (Questions with all user answers)
                    if !newsletter.formFields.isEmpty && !submissions.isEmpty {
                        combinedResponsesSection
                    }
                    
                    // Field-by-Field Analysis
                    if !newsletter.formFields.isEmpty {
                        fieldAnalysisSection
                    }
                    
                    // Timeline
                    submissionTimelineSection
                }
                .padding()
            }
            .navigationTitle("Form Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    // MARK: - Overall Statistics
    private var overallStatsSection: some View {
        VStack(spacing: 16) {
            Text("Overall Statistics")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: "Total Submissions",
                    value: "\(submissions.count)",
                    icon: "doc.text.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "Completion Rate",
                    value: completionRateString,
                    icon: "chart.bar.fill",
                    color: .green
                )
                
                StatCard(
                    title: "Avg Response Time",
                    value: averageResponseTime,
                    icon: "clock.fill",
                    color: .orange
                )
                
                StatCard(
                    title: "Unique Users",
                    value: "\(uniqueSubmitters.count)",
                    icon: "person.3.fill",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Status Breakdown
    private var statusBreakdownSection: some View {
        VStack(spacing: 16) {
            Text("Status Breakdown")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 12) {
                StatusRow(
                    status: .pending,
                    count: submissions.filter { $0.status == .pending }.count,
                    total: submissions.count
                )
                StatusRow(
                    status: .approved,
                    count: submissions.filter { $0.status == .approved }.count,
                    total: submissions.count
                )
                StatusRow(
                    status: .rejected,
                    count: submissions.filter { $0.status == .rejected }.count,
                    total: submissions.count
                )
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Combined Responses Section
    private var combinedResponsesSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("All Responses by Question")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Text("\(submissions.count) submissions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(8)
            }
            
            ForEach(newsletter.formFields) { field in
                QuestionResponsesCard(
                    field: field,
                    submissions: submissions
                )
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Field Analysis
    private var fieldAnalysisSection: some View {
        VStack(spacing: 16) {
            Text("Field-by-Field Analysis")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(newsletter.formFields) { field in
                FieldAnalysisCard(
                    field: field,
                    submissions: submissions
                )
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Submission Timeline
    private var submissionTimelineSection: some View {
        VStack(spacing: 16) {
            Text("Submission Timeline")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if submissions.isEmpty {
                Text("No submissions yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(submissions.prefix(10)) { submission in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(submission.submitterName)
                                .font(.headline)
                            Text(submission.submissionDate, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
                    }
                    
                    if submissions.count > 10 {
                        Text("and \(submissions.count - 10) more...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Computed Properties
    private var completionRateString: String {
        let totalFields = newsletter.formFields.count
        guard totalFields > 0, !submissions.isEmpty else { return "N/A" }
        
        let totalPossibleResponses = submissions.count * totalFields
        let actualResponses = submissions.reduce(0) { count, submission in
            count + submission.responses.values.filter { !$0.isEmpty }.count
        }
        
        let rate = (Double(actualResponses) / Double(totalPossibleResponses)) * 100
        return String(format: "%.0f%%", rate)
    }
    
    private var averageResponseTime: String {
        guard !submissions.isEmpty else { return "N/A" }
        
        let times = submissions.compactMap { submission -> TimeInterval? in
            // Calculate time between newsletter creation and submission
            return submission.submissionDate.timeIntervalSince(newsletter.date)
        }
        
        guard !times.isEmpty else { return "N/A" }
        
        let avgSeconds = times.reduce(0, +) / Double(times.count)
        let hours = Int(avgSeconds) / 3600
        let minutes = (Int(avgSeconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "< 1m"
        }
    }
    
    private var uniqueSubmitters: Set<String> {
        Set(submissions.map { $0.submitterId })
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
    }
}

// MARK: - Status Row
struct StatusRow: View {
    let status: NewsletterFormSubmission.SubmissionStatus
    let count: Int
    let total: Int
    
    var percentage: Double {
        guard total > 0 else { return 0 }
        return (Double(count) / Double(total)) * 100
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(status: status)
                Spacer()
                Text("\(count) of \(total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("(\(String(format: "%.0f%%", percentage)))")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(statusColor)
                        .frame(width: geometry.size.width * (percentage / 100), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
    }
    
    var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}

// MARK: - Field Analysis Card
struct FieldAnalysisCard: View {
    let field: NewsletterFormField
    let submissions: [NewsletterFormSubmission]
    @State private var isExpanded = false
    
    var responseCount: Int {
        submissions.filter { submission in
            if let response = submission.responses[field.id], !response.isEmpty {
                return true
            }
            return false
        }.count
    }
    
    var responseRate: Double {
        guard !submissions.isEmpty else { return 0 }
        return (Double(responseCount) / Double(submissions.count)) * 100
    }
    
    var allResponses: [String] {
        submissions.compactMap { $0.responses[field.id] }.filter { !$0.isEmpty }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.label)
                            .font(.headline)
                        Text(field.fieldType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(responseCount)/\(submissions.count)")
                            .font(.headline)
                        Text("(\(String(format: "%.0f%%", responseRate)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                Divider()
                
                if field.fieldType == .multipleChoice {
                    // Show distribution for choice-based fields
                    multipleChoiceAnalysis
                } else {
                    // Show sample responses for text fields
                    textResponsesPreview
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
    }
    
    private var multipleChoiceAnalysis: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Response Distribution")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(field.options, id: \.self) { option in
                let count = allResponses.filter { $0.contains(option) }.count
                let percentage = responseCount > 0 ? (Double(count) / Double(responseCount)) * 100 : 0
                
                HStack {
                    Text(option)
                        .font(.caption)
                    Spacer()
                    Text("\(count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("(\(String(format: "%.0f%%", percentage)))")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                            .cornerRadius(3)
                        
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * (percentage / 100), height: 6)
                            .cornerRadius(3)
                    }
                }
                .frame(height: 6)
            }
        }
    }
    
    private var textResponsesPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sample Responses")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if allResponses.isEmpty {
                Text("No responses yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(allResponses.prefix(3), id: \.self) { response in
                    Text("• \(response)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                if allResponses.count > 3 {
                    Text("+ \(allResponses.count - 3) more responses")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - Question Responses Card (Combined View)
struct QuestionResponsesCard: View {
    let field: NewsletterFormField
    let submissions: [NewsletterFormSubmission]
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(field.label)
                                .font(.headline)
                                .foregroundColor(.primary)
                            if field.isRequired {
                                Text("*")
                                    .foregroundColor(.red)
                            }
                        }
                        Text(field.fieldType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Text("\(responseCount)/\(submissions.count) answered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                Divider()
                
                // All User Responses
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(submissions) { submission in
                        UserResponseRow(
                            submission: submission,
                            field: field
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
    }
    
    private var responseCount: Int {
        submissions.filter { submission in
            if let response = submission.responses[field.id], !response.isEmpty {
                return true
            }
            return false
        }.count
    }
}

// MARK: - User Response Row
struct UserResponseRow: View {
    let submission: NewsletterFormSubmission
    let field: NewsletterFormField
    
    var response: String? {
        submission.responses[field.id]
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // User Info
            VStack(alignment: .leading, spacing: 2) {
                Text(submission.submitterName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(submission.submitterEmail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(submission.submissionDate, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 140, alignment: .leading)
            
            // Response
            VStack(alignment: .leading, spacing: 4) {
                if let response = response, !response.isEmpty {
                    Text(response)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No response")
                        .font(.subheadline)
                        .italic()
                        .foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(response != nil && !response!.isEmpty ? Color.blue.opacity(0.15) : Color(uiColor: .tertiarySystemBackground))
        )
    }
}

extension NewsletterFormFieldType {
    var displayName: String {
        switch self {
        case .shortText: return "Short Text"
        case .longText: return "Long Text"
        case .email: return "Email"
        case .phone: return "Phone"
        case .number: return "Number"
        case .date: return "Date"
        case .multipleChoice: return "Multiple Choice"
        }
    }
}

// MARK: - Custom Checkbox Toggle Style
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 20))
                .foregroundColor(configuration.isOn ? .accentColor : .gray)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            
            configuration.label
        }
    }
}
