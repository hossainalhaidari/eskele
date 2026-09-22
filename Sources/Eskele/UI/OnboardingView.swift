import SwiftUI

/// Shown once, on first launch.
///
/// Its only real job is to get consent for the one thing Eskele does that reaches outside itself:
/// taking over the system Dock. Everything else can be discovered from the menu bar item.
struct OnboardingView: View {
    var onChoose: (_ hideSystemDock: Bool, _ reserveSpace: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Eskele is running").font(.title2).bold()
                Text("Look for its icon in the menu bar — that is where every setting lives.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Do you want Eskele to replace your Dock?").font(.headline)
                Text("""
                    Eskele can hide the system Dock so you do not have two. Your Dock settings are \
                    backed up first and restored whenever Eskele quits — including after a crash.
                    """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Keep Both for Now") { onChoose(false, false) }
                Spacer()
                Button("Replace My Dock") { onChoose(true, true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
