import SwiftUI

struct DeviceScanView: View {
    @EnvironmentObject var bluetooth: BandBluetoothManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !bluetooth.isBluetoothReady {
                    Text("Turn on Bluetooth to scan for devices.")
                        .foregroundStyle(.secondary)
                } else if bluetooth.discoveredDevices.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Scanning…")
                    }
                }
                ForEach(bluetooth.discoveredDevices) { device in
                    let isConnected = bluetooth.connectedDevices.contains(device)
                    Button {
                        guard !isConnected else { return }
                        bluetooth.connect(to: device)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name).font(.body)
                                Text("RSSI \(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isConnected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .disabled(isConnected)
                }
            }
            .navigationTitle("Nearby Devices")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { bluetooth.startScanning() }
            .onDisappear { bluetooth.stopScanning() }
        }
    }
}
