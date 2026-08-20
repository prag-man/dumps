import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @StateObject private var preferences = Preferences.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 320).padding(16)
        .background(Theme.window(for: scheme))
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $preferences.launchAtLogin)
                    .font(.system(size: 12.5)).tint(Theme.violet)
                    .help("Start Dumps when you log in")
                Toggle("Show Menu Bar Icon", isOn: $preferences.showMenuBarIcon)
                    .font(.system(size: 12.5)).tint(Theme.violet)
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(Appearance.allCases) { a in Text(a.displayName).font(.system(size: 12.5)).tag(a.rawValue) }
                }.pickerStyle(.segmented).controlSize(.small)
            } header: {
                Text("General").font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.textTertiary(for: scheme))
            }

            Section {
                HStack {
                    Text("Global Shortcut").font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary(for: scheme))
                    Spacer()
                    Text("⌥ Space").font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary(for: scheme))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.raised(for: scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.hairlineBorder(for: scheme), lineWidth: DumpsMetrics.hairline))
                        .help("Global hotkey is currently fixed to Option-Space")
                }
                Text("Press ⌥Space from anywhere to capture a dump.").font(.system(size: 11)).foregroundStyle(Theme.textTertiary(for: scheme))
            } header: {
                Text("Capture").font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.textTertiary(for: scheme))
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.violetSoft).frame(width: 48, height: 48)
                Image(systemName: "tray.full.fill").font(.system(size: 22, weight: .regular)).foregroundStyle(Theme.violet)
            }
            Text("Dumps").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textPrimary(for: scheme))
            Text(versionString).font(.system(size: 11, weight: .regular, design: .monospaced)).foregroundStyle(Theme.textTertiary(for: scheme))
            Text("A calm, native scratchpad for macOS.").font(.system(size: 12)).foregroundStyle(Theme.textSecondary(for: scheme))
            Link("View on GitHub", destination: URL(string: "https://github.com/prag-man/dumps")!)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.violet)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).multilineTextAlignment(.center)
    }

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(v) (\(b))"
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider { static var previews: some View { SettingsView() } }
#endif
