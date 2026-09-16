import SwiftUI

struct DeviceScanView: View {
    @EnvironmentObject var bluetooth: BandBluetoothManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !bluetooth.isBluetoothReady {
                    Text("Turn on Bluetooth to scan for your band.")
                        .foregroundStyle(.secondary)
                } else if bluetooth.discoveredDevices.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Scanning…")
                    }
                }
                ForEach(bluetooth.discoveredDevices) { device in
                    Button {
                        bluetooth.connect(to: device)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name).font(.body)
                                Text("RSSI \(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Nearby Bands")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { bluetooth.startScanning() }
            .onDisappear { bluetooth.stopScanning() }
        }
    }
}
