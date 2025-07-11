import SwiftUI

// MARK: - Color Extensions
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}

// MARK: - App Preferences
class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    
    @Published var isDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
        }
    }
    
    @Published var hideCompletedTasks: Bool {
        didSet {
            UserDefaults.standard.set(hideCompletedTasks, forKey: "hideCompletedTasks")
        }
    }
    
    @Published var personalColor: Color {
        didSet {
            UserDefaults.standard.set(personalColor.toHex(), forKey: "personalColor")
        }
    }
    
    @Published var professionalColor: Color {
        didSet {
            UserDefaults.standard.set(professionalColor.toHex(), forKey: "professionalColor")
        }
    }
    
    @Published var hideRecurringEventsInMonth: Bool {
        didSet {
            UserDefaults.standard.set(hideRecurringEventsInMonth, forKey: "hideRecurringEventsInMonth")
        }
    }
    
    @Published var weekViewVersion: Int {
        didSet {
            UserDefaults.standard.set(weekViewVersion, forKey: "weekViewVersion")
        }
    }
    
    private init() {
        self.isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        self.hideCompletedTasks = UserDefaults.standard.bool(forKey: "hideCompletedTasks")
        self.hideRecurringEventsInMonth = UserDefaults.standard.bool(forKey: "hideRecurringEventsInMonth")
        self.weekViewVersion = UserDefaults.standard.integer(forKey: "weekViewVersion")
        
        // Load colors from UserDefaults or use defaults
        let personalHex = UserDefaults.standard.string(forKey: "personalColor") ?? "#dcd6ff"
        let professionalHex = UserDefaults.standard.string(forKey: "professionalColor") ?? "#38eb50"
        
        self.personalColor = Color(hex: personalHex) ?? Color(hex: "#dcd6ff") ?? .purple
        self.professionalColor = Color(hex: professionalHex) ?? Color(hex: "#38eb50") ?? .green
    }
    
    func updateDarkMode(_ value: Bool) {
        isDarkMode = value
    }
    
    func updateHideCompletedTasks(_ value: Bool) {
        hideCompletedTasks = value
    }
    
    func updatePersonalColor(_ color: Color) {
        personalColor = color
    }
    
    func updateProfessionalColor(_ color: Color) {
        professionalColor = color
    }
    
    func updateHideRecurringEventsInMonth(_ value: Bool) {
        hideRecurringEventsInMonth = value
    }
    
    func updateWeekViewVersion(_ value: Int) {
        weekViewVersion = value
    }
}

struct SettingsView: View {
    @ObservedObject private var auth = GoogleAuthManager.shared
    @StateObject private var appPrefs = AppPreferences.shared
    
    // State for show/hide account toggles (placeholder for future implementation)
    @State private var showPersonalAccount = true
    @State private var showProfessionalAccount = true
    
    // State for color picker modals
    @State private var showingPersonalColorPicker = false
    @State private var showingProfessionalColorPicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Linked Accounts") {
                    accountRow(
                        kind: "Personal", 
                        kindEnum: .personal,
                        isVisible: $showPersonalAccount,
                        accountColor: $appPrefs.personalColor,
                        showingColorPicker: $showingPersonalColorPicker
                    )
                    accountRow(
                        kind: "Professional", 
                        kindEnum: .professional,
                        isVisible: $showProfessionalAccount,
                        accountColor: $appPrefs.professionalColor,
                        showingColorPicker: $showingProfessionalColorPicker
                    )
                }
                
                // Task Management section removed (Hide Completed Tasks now controlled via eye icon)
                
                Section("Calendar Management") {
                    HStack {
                        Image(systemName: "repeat")
                            .foregroundColor(.secondary)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hide Recurring Events in Month View")
                                .font(.body)
                            Text("Hide likely recurring events in month calendar view")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { appPrefs.hideRecurringEventsInMonth },
                            set: { appPrefs.updateHideRecurringEventsInMonth($0) }
                        ))
                    }
                    
                    // Week View Version Picker
                    HStack {
                        Image(systemName: "rectangle.3.offgrid")
                            .foregroundColor(.secondary)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Week View Layout")
                                .font(.body)
                            Text("Choose how the week screen displays tasks/events")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Picker("Week View", selection: Binding(
                            get: { appPrefs.weekViewVersion },
                            set: { appPrefs.updateWeekViewVersion($0) }
                        )) {
                            Text("Weekly").tag(1)
                            Text("Daily").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
                
                Section("App Preferences") {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.secondary)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dark Mode")
                                .font(.body)
                            Text("Use dark appearance")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { appPrefs.isDarkMode },
                            set: { appPrefs.updateDarkMode($0) }
                        ))
                    }
                    
                    HStack {
                        Image(systemName: "photo.circle")
                            .foregroundColor(.secondary)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Custom Cover Image")
                                .font(.body)
                            Text("Upload your own cover image")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Upload") {
                            // TODO: Implement cover image upload functionality
                            print("Cover image upload tapped - not yet implemented")
                        }
                        .disabled(true) // Disabled for now since it's not implemented
                        .foregroundColor(.secondary)
                    }
                }
                
                Section("Debug & Testing") {
                    HStack {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .foregroundColor(.secondary)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test Firestore Connection")
                                .font(.body)
                            Text("Write a test document to verify database connection")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Test") {
                            Task {
                                await FirestoreManager.shared.testFirestoreConnection()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    HStack {
                        Image(systemName: "person.2.badge.gearshape")
                            .foregroundColor(.secondary)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test Google Sign-In Config")
                                .font(.body)
                            Text("Verify Google Sign-In is properly configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Debug") {
                            testGoogleSignInConfig()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    HStack {
                        Image(systemName: "trash.circle")
                            .foregroundColor(.secondary)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear Auth Tokens")
                                .font(.body)
                            Text("Reset all Google authentication tokens")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Clear") {
                            clearAllAuthTokens()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .sidebarToggleHidden()
        }
    }
    
    @ViewBuilder
    private func accountRow(
        kind: String, 
        kindEnum: GoogleAuthManager.AccountKind,
        isVisible: Binding<Bool>,
        accountColor: Binding<Color>,
        showingColorPicker: Binding<Bool>
    ) -> some View {
        let isLinked = auth.linkedStates[kindEnum] ?? false
        HStack(spacing: 16) {
            // Eye toggle for show/hide account
            Button {
                // TODO: Implement show/hide account functionality
                isVisible.wrappedValue.toggle()
                print("\(kind) account visibility toggled to: \(isVisible.wrappedValue)")
            } label: {
                Image(systemName: isVisible.wrappedValue ? "eye" : "eye.slash")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            // Color picker circle
            Button {
                showingColorPicker.wrappedValue = true
            } label: {
                Circle()
                    .fill(accountColor.wrappedValue)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: showingColorPicker) {
                ColorPickerSheet(
                    title: "\(kind) Account Color",
                    selectedColor: accountColor,
                    onColorChange: { color in
                        switch kindEnum {
                        case .personal:
                            appPrefs.updatePersonalColor(color)
                        case .professional:
                            appPrefs.updateProfessionalColor(color)
                        }
                    }
                )
            }
            
            // Account info
            VStack(alignment: .leading, spacing: 2) {
                Text(kind)
                    .font(.body)
                Text(isLinked ? (auth.getEmail(for: kindEnum).isEmpty ? "Linked" : auth.getEmail(for: kindEnum)) : "Not Linked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Link/Unlink button
            Button(isLinked ? "Unlink" : "Link") {
                handleTap(kindEnum)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func handleTap(_ kind: GoogleAuthManager.AccountKind) {
        if auth.isLinked(kind: kind) {
            print("🔓 Unlinking \(kind) account")
            auth.unlink(kind: kind)
        } else {
            print("🔗 Linking \(kind) account...")
            Task {
                do {
                    try await auth.link(kind: kind, presenting: nil)
                    print("✅ Successfully linked \(kind) account")
                } catch GoogleAuthManager.AuthError.missingClientID {
                    print("❌ Failed to link \(kind) account: Missing Client ID in Info.plist")
                    // Show user-friendly error message
                } catch GoogleAuthManager.AuthError.noRefreshToken {
                    print("❌ Failed to link \(kind) account: No refresh token available")
                } catch GoogleAuthManager.AuthError.tokenRefreshFailed {
                    print("❌ Failed to link \(kind) account: Token refresh failed")
                } catch {
                    print("❌ Failed to link \(kind) account: \(error)")
                    print("❌ Error type: \(type(of: error))")
                    print("❌ Error description: \(error.localizedDescription)")
                    
                    // If it's a Google Sign-In error, try to provide more details
                    if let nsError = error as NSError? {
                        print("❌ NSError domain: \(nsError.domain)")
                        print("❌ NSError code: \(nsError.code)")
                        print("❌ NSError userInfo: \(nsError.userInfo)")
                    }
                }
            }
        }
    }
    
    private func testGoogleSignInConfig() {
        print("🧪 Testing Google Sign-In Configuration...")
        
        // Check Info.plist configuration
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
            print("✅ GIDClientID found: \(clientID)")
        } else {
            print("❌ GIDClientID not found in Info.plist")
        }
        
        if let googleClientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String {
            print("✅ GOOGLE_CLIENT_ID found: \(googleClientID)")
        } else {
            print("❌ GOOGLE_CLIENT_ID not found in Info.plist")
        }
        
        // Check URL schemes
        if let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] {
            print("✅ Found \(urlTypes.count) URL types")
            for (index, urlType) in urlTypes.enumerated() {
                if let schemes = urlType["CFBundleURLSchemes"] as? [String] {
                    print("  URL Type \(index): \(schemes)")
                }
            }
        } else {
            print("❌ No CFBundleURLTypes found in Info.plist")
        }
        
        // Check current authentication states
        print("📊 Current auth states:")
        print("  Personal linked: \(auth.isLinked(kind: .personal))")
        print("  Personal email: \(auth.getEmail(for: .personal))")
        print("  Professional linked: \(auth.isLinked(kind: .professional))")
        print("  Professional email: \(auth.getEmail(for: .professional))")
        
        // Check UserDefaults for tokens
        print("🔍 Checking UserDefaults for stored tokens...")
        let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.contains("google") }
        print("  Found \(keys.count) Google-related keys: \(keys.sorted())")
        
        print("✅ Google Sign-In configuration test completed!")
    }
    
    private func clearAllAuthTokens() {
        print("🗑️ Clearing all Google authentication tokens...")
        
        // Get all Google-related UserDefaults keys
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
        let googleKeys = allKeys.filter { $0.contains("google") }
        
        print("🔍 Found \(googleKeys.count) Google-related keys to clear: \(googleKeys.sorted())")
        
        // Remove all Google-related keys
        for key in googleKeys {
            UserDefaults.standard.removeObject(forKey: key)
            print("  🗑️ Removed key: \(key)")
        }
        
        // Force update authentication states
        auth.unlink(kind: .personal)
        auth.unlink(kind: .professional)
        
        print("✅ All Google authentication tokens cleared!")
        print("📝 You can now try linking accounts again.")
    }
}

// MARK: - Color Picker Sheet Component
struct ColorPickerSheet: View {
    let title: String
    @Binding var selectedColor: Color
    let onColorChange: (Color) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ColorPicker("Select Color", selection: $selectedColor, supportsOpacity: false)
                    .labelsHidden()
                    .padding()
                
                Button("Done") {
                    onColorChange(selectedColor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Color Picker Row Component (Legacy)
struct ColorPickerRow: View {
    let title: String
    let icon: String
    @Binding var selectedColor: Color
    let onColorChange: (Color) -> Void
    
    @State private var showingColorPicker = false
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(selectedColor)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text("Tap to customize")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Color preview circle
            Circle()
                .fill(selectedColor)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingColorPicker = true
        }
        .sheet(isPresented: $showingColorPicker) {
            ColorPickerSheet(
                title: title,
                selectedColor: $selectedColor,
                onColorChange: onColorChange
            )
        }
    }
}



#Preview {
    SettingsView()
} 