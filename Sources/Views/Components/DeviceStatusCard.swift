import SwiftUI

struct DeviceStatusCard: View {
    @EnvironmentObject var bluetooth: BandBluetoothManager

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(bluetooth.connectedDevice?.name ?? "No band connected")
                    .font(.subheadline.bold())
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = bluetooth.latestReadings[.battery] {
                Text("\(Int(battery.value))%")
                    .font(.caption.bold())
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusText: String {
        switch bluetooth.connectionState {
        case .connected: return "Connected · syncing to Health"
        case .connecting: return "Connecting…"
        case .scanning: return "Scanning for bands…"
        case .disconnected: return "Go to Sensors to pair a band"
        case .failed(let reason): return reason
        }
    }

    private var iconName: String {
        switch bluetooth.connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .scanning: return "antenna.radiowaves.left.and.right"
        default: return "exclamationmark.circle"
        }
    }

    private var iconColor: Color {
        switch bluetooth.connectionState {
        case .connected: return .green
        case .failed: return .red
        default: return .orange
        }
    }
}
