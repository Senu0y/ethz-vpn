import SwiftUI
import ServiceManagement

struct VPNAccessView: View {
    @State private var description = PrivilegedHelper.statusDescription
    @State private var enabled = PrivilegedHelper.isEnabled
    @State private var message: String?
    @State private var busy = false
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VPN Access").font(.headline)
            Text(description).font(.callout).foregroundStyle(.secondary)
            Text("Credentials stay in your Keychain. macOS approval allows the VPN to configure networking.")
                .font(.caption).foregroundStyle(.secondary)
            if let message { Text(message).font(.callout).foregroundStyle(.red) }
            HStack {
                Button(enabled ? "Disable VPN Access" : "Enable VPN Access") {
                    busy = true
                    message = nil
                    let done: (String?) -> Void = { error in
                        message = error
                        busy = false
                        update()
                    }
                    if enabled { PrivilegedHelper.disable(completion: done) }
                    else { PrivilegedHelper.enable(completion: done) }
                }.disabled(busy)
                Button("System Settings") { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .onReceive(refresh) { _ in
            let wasEnabled = enabled
            update()
            if !wasEnabled && enabled {
                message = nil
            }
        }
    }

    private func update() {
        enabled = PrivilegedHelper.isEnabled
        description = PrivilegedHelper.statusDescription
    }
}
