import SwiftUI

struct DeviceStatusCard: View {
    @EnvironmentObject var bluetooth: BandBluetoothManager

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.subheadline.bold())
                Text(subtitleText)
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

    private var titleText: String {
        switch bluetooth.connectedDevices.count {
        case 0: return "No devices connected"
        case 1: return bluetooth.connectedDevices[0].name
        default: return "\(bluetooth.connectedDevices.count) devices connected"
        }
    }

    private var subtitleText: String {
        if bluetooth.connectedDevices.isEmpty {
            return "Go to Sensors to pair a device"
        }
        if bluetooth.connectedDevices.count == 1 {
            return "Connected · syncing to Health"
        }
        return bluetooth.connectedDevices.map(\.name).joined(separator: ", ")
    }

    private var iconName: String {
        bluetooth.connectedDevices.isEmpty ? "exclamationmark.circle" : "checkmark.circle.fill"
    }

    private var iconColor: Color {
        bluetooth.connectedDevices.isEmpty ? .orange : .green
    }
}
