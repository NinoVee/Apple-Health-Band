import Foundation
import CoreBluetooth

/// Decoders for the standard Bluetooth SIG GATT characteristics declared
/// in `GattProfiles.swift`. Each function follows the byte layout from the
/// Bluetooth SIG's GATT Specification Supplement.
/// Pure, stateless decoding — explicitly `nonisolated` so it can be called
/// synchronously from Core Bluetooth's nonisolated delegate callbacks even
/// when the app's default actor isolation is set to `MainActor`.
enum SensorParsers {
    nonisolated static func decode(characteristicUUID: CBUUID, data: Data) -> [SensorReading] {
        switch characteristicUUID {
        case GattCharacteristic.heartRateMeasurement:
            return heartRate(from: data).map { [$0] } ?? []
        case GattCharacteristic.batteryLevel:
            return batteryLevel(from: data).map { [$0] } ?? []
        case GattCharacteristic.pulseOximeterMeasurement:
            return pulseOximeter(from: data).map { [$0] } ?? []
        case GattCharacteristic.rscMeasurement:
            return rscCadenceAndDistance(from: data)
        case GattCharacteristic.bodyCompositionMeasurement:
            return bodyComposition(from: data)
        default:
            return []
        }
    }

    /// Heart Rate Measurement (0x2A37): flags byte, then an 8- or 16-bit
    /// beats-per-minute value depending on flag bit 0.
    nonisolated static func heartRate(from data: Data) -> SensorReading? {
        guard let flags = data.first else { return nil }
        let isUInt16 = (flags & 0x01) != 0
        let base = data.startIndex
        let value: Double
        if isUInt16 {
            guard data.count >= 3 else { return nil }
            let raw = UInt16(data[base + 1]) | (UInt16(data[base + 2]) << 8)
            value = Double(raw)
        } else {
            guard data.count >= 2 else { return nil }
            value = Double(data[base + 1])
        }
        return SensorReading(kind: .heartRate, value: value, unit: "bpm", timestamp: Date())
    }

    /// Battery Level (0x2A19): a single percentage byte.
    nonisolated static func batteryLevel(from data: Data) -> SensorReading? {
        guard let byte = data.first else { return nil }
        return SensorReading(kind: .battery, value: Double(byte), unit: "%", timestamp: Date())
    }

    /// Pulse Oximeter Spot-check Measurement (0x2A5E): flags(1) +
    /// SpO2 SFLOAT(2) + pulse rate SFLOAT(2) + optional fields.
    nonisolated static func pulseOximeter(from data: Data) -> SensorReading? {
        guard data.count >= 5 else { return nil }
        let base = data.startIndex
        let raw = UInt16(data[base + 1]) | (UInt16(data[base + 2]) << 8)
        guard let spo2 = sfloat(raw) else { return nil }
        return SensorReading(kind: .spo2, value: spo2, unit: "%", timestamp: Date())
    }

    /// Running Speed and Cadence Measurement (0x2A53): flags(1) +
    /// speed(2, unused here) + cadence(1) + optional stride length(2) +
    /// optional total distance(4, 1/10 meter resolution).
    ///
    /// Cadence is reported as an approximate steps-per-minute rate, not a
    /// literal step count — see `ActivitySyncCoordinator` for how it's
    /// turned into a cumulative step total.
    nonisolated static func rscCadenceAndDistance(from data: Data) -> [SensorReading] {
        guard data.count >= 4 else { return [] }
        var offset = data.startIndex
        let flags = data[offset]; offset += 1
        offset += 2 // instantaneous speed — not surfaced by this app
        let cadence = data[offset]; offset += 1

        var readings = [SensorReading(kind: .steps, value: Double(cadence), unit: "spm", timestamp: Date())]

        let strideLengthPresent = (flags & 0x01) != 0
        let totalDistancePresent = (flags & 0x02) != 0
        if strideLengthPresent { offset += 2 }
        if totalDistancePresent, data.count >= offset + 4 {
            let raw = data[offset...].prefix(4).reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let meters = Double(raw) / 10.0
            readings.append(SensorReading(kind: .distance, value: meters, unit: "m", timestamp: Date()))
        }
        return readings
    }

    /// Body Composition Measurement (0x2A9C): a 16-bit flags field, then
    /// body fat percentage (always present), then optional fields in a
    /// fixed order per the Bluetooth SIG spec — this app only surfaces
    /// body fat %, fat-free mass (mapped to HealthKit's `leanBodyMass`),
    /// and weight; basal metabolic rate, muscle %, impedance, and height
    /// are parsed (to keep offsets correct) but not surfaced.
    nonisolated static func bodyComposition(from data: Data) -> [SensorReading] {
        guard data.count >= 4 else { return [] }
        var offset = data.startIndex

        func readUInt16() -> UInt16? {
            guard data.count >= offset + 2 else { return nil }
            let value = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            offset += 2
            return value
        }

        guard let flags = readUInt16() else { return [] }
        let imperial = (flags & 0x0001) != 0
        let hasTimeStamp = (flags & 0x0002) != 0
        let hasUserID = (flags & 0x0004) != 0
        let hasBMR = (flags & 0x0008) != 0
        let hasMusclePercentage = (flags & 0x0010) != 0
        let hasMuscleMass = (flags & 0x0020) != 0
        let hasFatFreeMass = (flags & 0x0040) != 0
        let hasSoftLeanMass = (flags & 0x0080) != 0
        let hasBodyWaterMass = (flags & 0x0100) != 0
        let hasImpedance = (flags & 0x0200) != 0
        let hasWeight = (flags & 0x0400) != 0

        guard let fatPercentRaw = readUInt16() else { return [] }
        let now = Date()
        var readings = [SensorReading(kind: .bodyFatPercentage, value: Double(fatPercentRaw) * 0.1, unit: "%", timestamp: now)]

        if hasTimeStamp { offset += 7 }
        if hasUserID { offset += 1 }
        if hasBMR { _ = readUInt16() } // kJ — not surfaced by this app
        if hasMusclePercentage { _ = readUInt16() }
        if hasMuscleMass { _ = readUInt16() }

        // Mass fields share a resolution: 0.005 kg (SI) or 0.01 lb (imperial).
        func massInKilograms(_ raw: UInt16) -> Double {
            imperial ? Double(raw) * 0.01 * 0.45359237 : Double(raw) * 0.005
        }

        if hasFatFreeMass, let fatFreeMassRaw = readUInt16() {
            readings.append(SensorReading(kind: .leanBodyMass, value: massInKilograms(fatFreeMassRaw), unit: "kg", timestamp: now))
        }
        if hasSoftLeanMass { _ = readUInt16() }
        if hasBodyWaterMass { _ = readUInt16() }
        if hasImpedance { _ = readUInt16() } // 0.1 Ohm — not surfaced by this app
        if hasWeight, let weightRaw = readUInt16() {
            readings.append(SensorReading(kind: .bodyMass, value: massInKilograms(weightRaw), unit: "kg", timestamp: now))
        }
        // Height, if present, follows here — not surfaced by this app.

        return readings
    }

    /// IEEE-11073 16-bit SFLOAT decode used by SpO2 measurements: a 4-bit
    /// exponent (bits 12-15) and 12-bit mantissa (bits 0-11), both signed.
    nonisolated private static func sfloat(_ raw: UInt16) -> Double? {
        guard raw != 0x07FF, raw != 0x0800 else { return nil } // NaN / NRes
        let mantissa = Int16(bitPattern: raw << 4) >> 4
        let exponent = Int8(bitPattern: UInt8((raw >> 12) & 0x0F) << 4) >> 4
        return Double(mantissa) * pow(10.0, Double(exponent))
    }
}
