import AppKit
import SwiftUI

let flowAccent = Color(red: 1, green: 0.38, blue: 0.27)

private enum HubSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case history = "History"
    case readAloud = "Read aloud"

    var id: Self { self }

    var icon: String {
        switch self {
        case .home: "house"
        case .history: "clock"
        case .readAloud: "speaker.wave.2"
        }
    }
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var model: AppModel
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @SceneStorage("selectedHubSection") private var selectedSection = HubSection.home.rawValue
    @State private var didOpenFlowBar = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(flowAccent, in: RoundedRectangle(cornerRadius: 9))
                    Text("tk")
                        .font(.title2.bold())
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)

                List(HubSection.allCases, selection: selection) { section in
                    Label(section.rawValue, systemImage: section.icon)
                        .tag(section)
                }
                .listStyle(.sidebar)

                Label(
                    model.accessibilityGranted ? "Ready everywhere" : "Permission needed",
                    systemImage: model.accessibilityGranted
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(model.accessibilityGranted ? .green : .orange)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
        } detail: {
            switch currentSection {
            case .home:
                HomeView(model: model)
            case .history:
                HistoryView(model: model)
            case .readAloud:
                ReadAloudView(model: model)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(flowAccent)
        .frame(minWidth: 780, minHeight: 560)
        .onAppear {
            openFlowBarIfReady()
        }
        .onChange(of: didCompleteOnboarding) {
            openFlowBarIfReady()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            model.refreshPermissions()
        }
        .sheet(isPresented: onboardingPresented) {
            OnboardingView(model: model) {
                didCompleteOnboarding = true
            }
            .interactiveDismissDisabled()
        }
    }

    private var currentSection: HubSection {
        HubSection(rawValue: selectedSection) ?? .home
    }

    private var selection: Binding<HubSection?> {
        Binding(
            get: { currentSection },
            set: { selectedSection = ($0 ?? .home).rawValue }
        )
    }

    private var onboardingPresented: Binding<Bool> {
        Binding(
            get: { !didCompleteOnboarding },
            set: { _ in }
        )
    }

    private func openFlowBarIfReady() {
        guard didCompleteOnboarding, !didOpenFlowBar else { return }
        didOpenFlowBar = true
        openWindow(id: "flow-bar")
    }
}
