import Foundation
import CoreBluetooth

struct BandDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

extension BandDevice: Equatable {
    static func == (lhs: BandDevice, rhs: BandDevice) -> Bool {
        lhs.id == rhs.id
    }
}
