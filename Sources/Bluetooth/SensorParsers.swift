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
            return heartRate(from: data)
        case GattCharacteristic.batteryLevel:
            return batteryLevel(from: data).map { [$0] } ?? []
        case GattCharacteristic.pulseOximeterMeasurement:
            return pulseOximeter(from: data).map { [$0] } ?? []
        case GattCharacteristic.rscMeasurement:
            return rscCadenceAndDistance(from: data)
        case GattCharacteristic.bodyCompositionMeasurement:
            return bodyComposition(from: data)
        case GattCharacteristic.temperatureMeasurement:
            return bodyTemperature(from: data).map { [$0] } ?? []
        case GattCharacteristic.bloodPressureMeasurement:
            return bloodPressure(from: data)
        default:
            logUnhandled(characteristicUUID: characteristicUUID, data: data)
            return []
        }
    }

    /// Prints the raw bytes from any characteristic this app doesn't
    /// have a decoder for — e.g. VWAR MG's proprietary services (see
    /// `VendorService.vwarMG`), which have no known protocol yet. Watch
    /// Xcode's console while triggering a specific, known action (a
    /// heart-rate reading, a step, opening the band's own app) so the
    /// timing/context of what comes back can be matched to a byte
    /// layout. Debug-only — never runs in a Release build.
    nonisolated private static func logUnhandled(characteristicUUID: CBUUID, data: Data) {
        #if DEBUG
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[SensorParsers] unhandled characteristic \(characteristicUUID): \(hex)")
        #endif
    }

    /// Heart Rate Measurement (0x2A37): flags byte, then an 8- or 16-bit
    /// beats-per-minute value (flag bit 0), optional Energy Expended (bit
    /// 3) — a UINT16 in kJ, a running total since the band last reset it,
    /// not a per-sample amount, converted to kcal here — then zero or more
    /// RR-Interval values (bit 4) — beat-to-beat intervals in 1/1024s, the
    /// raw data HRV metrics are computed from. See `ActivitySyncCoordinator`
    /// for how RR intervals become an SDNN estimate written to Health as
    /// `heartRateVariabilitySDNN`, and how the Energy Expended running
    /// total becomes incremental `activeEnergyBurned` writes.
    nonisolated static func heartRate(from data: Data) -> [SensorReading] {
        guard let flags = data.first else { return [] }
        let base = data.startIndex
        let isUInt16 = (flags & 0x01) != 0
        let energyExpendedPresent = (flags & 0x08) != 0
        let rrIntervalPresent = (flags & 0x10) != 0
        let now = Date()

        let hrValue: Double
        var offset: Int
        if isUInt16 {
            guard data.count >= 3 else { return [] }
            hrValue = Double(UInt16(data[base + 1]) | (UInt16(data[base + 2]) << 8))
            offset = 3
        } else {
            guard data.count >= 2 else { return [] }
            hrValue = Double(data[base + 1])
            offset = 2
        }

        var readings = [SensorReading(kind: .heartRate, value: hrValue, unit: "bpm", timestamp: now)]

        if energyExpendedPresent {
            if data.count >= offset + 2 {
                let kilojoules = UInt16(data[base + offset]) | (UInt16(data[base + offset + 1]) << 8)
                readings.append(SensorReading(kind: .calories, value: Double(kilojoules) / 4.184, unit: "kcal", timestamp: now))
            }
            offset += 2
        }

        if rrIntervalPresent {
            while data.count >= offset + 2 {
                let raw = UInt16(data[base + offset]) | (UInt16(data[base + offset + 1]) << 8)
                offset += 2
                let milliseconds = Double(raw) / 1024.0 * 1000.0
                readings.append(SensorReading(kind: .rrInterval, value: milliseconds, unit: "ms", timestamp: now))
            }
        }

        return readings
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

    /// Health Thermometer Measurement (0x2A1C): flags(1) + temperature
    /// IEEE-11073 32-bit FLOAT(4) + optional time stamp(7) + optional
    /// temperature type(1). Always normalized to Celsius.
    nonisolated static func bodyTemperature(from data: Data) -> SensorReading? {
        guard data.count >= 5 else { return nil }
        let base = data.startIndex
        let flags = data[base]
        let isFahrenheit = (flags & 0x01) != 0
        guard let raw = float32(data[(base + 1)...]) else { return nil }
        let celsius = isFahrenheit ? (raw - 32) * 5.0 / 9.0 : raw
        return SensorReading(kind: .bodyTemperature, value: celsius, unit: "°C", timestamp: Date())
    }

    /// Blood Pressure Measurement (0x2A35): flags(1) + systolic SFLOAT(2)
    /// + diastolic SFLOAT(2) + mean arterial pressure SFLOAT(2, parsed to
    /// keep offsets correct but not surfaced) + optional time stamp(7) +
    /// optional pulse rate SFLOAT(2) + optional user ID(1) + optional
    /// measurement status(2). Values are always mmHg — kPa readings are
    /// converted, since HealthKit's blood pressure types are mmHg-based.
    ///
    /// Systolic and diastolic are paired into one `HKCorrelation` by
    /// `ActivitySyncCoordinator` (see its `.bloodPressureDiastolic`
    /// case), since Health expects them written together, not as two
    /// independent samples. Pulse rate, if present, is surfaced as an
    /// ordinary `.heartRate` reading — it's a real heart rate value
    /// regardless of which sensor took it.
    nonisolated static func bloodPressure(from data: Data) -> [SensorReading] {
        guard data.count >= 7 else { return [] }
        let base = data.startIndex
        var offset = 1

        func readSFloat() -> Double? {
            guard data.count >= offset + 2 else { return nil }
            let raw = UInt16(data[base + offset]) | (UInt16(data[base + offset + 1]) << 8)
            offset += 2
            return sfloat(raw)
        }

        let flags = data[base]
        let isKPa = (flags & 0x01) != 0
        let hasTimeStamp = (flags & 0x02) != 0
        let hasPulseRate = (flags & 0x04) != 0

        func mmHg(_ value: Double) -> Double {
            isKPa ? value * 7.500617 : value
        }

        guard let systolicRaw = readSFloat(), let diastolicRaw = readSFloat(), readSFloat() != nil else { return [] }
        let now = Date()
        var readings = [
            SensorReading(kind: .bloodPressureSystolic, value: mmHg(systolicRaw), unit: "mmHg", timestamp: now),
            SensorReading(kind: .bloodPressureDiastolic, value: mmHg(diastolicRaw), unit: "mmHg", timestamp: now)
        ]

        if hasTimeStamp { offset += 7 }
        if hasPulseRate, let pulseRate = readSFloat() {
            readings.append(SensorReading(kind: .heartRate, value: pulseRate, unit: "bpm", timestamp: now))
        }

        return readings
    }

    /// IEEE-11073 32-bit FLOAT decode used by temperature measurements: a
    /// signed 8-bit exponent (byte 3) and signed 24-bit mantissa (bytes
    /// 0-2, little-endian), value = mantissa * 10^exponent.
    nonisolated private static func float32(_ data: Data) -> Double? {
        guard data.count >= 4 else { return nil }
        let base = data.startIndex
        let mantissaUnsigned = UInt32(data[base]) | (UInt32(data[base + 1]) << 8) | (UInt32(data[base + 2]) << 16)
        guard mantissaUnsigned != 0x0080_0000 else { return nil } // NaN
        var mantissaRaw = mantissaUnsigned
        if mantissaRaw & 0x0080_0000 != 0 { mantissaRaw |= 0xFF00_0000 } // sign-extend 24-bit to 32-bit
        let mantissa = Int32(bitPattern: mantissaRaw)
        let exponent = Int8(bitPattern: data[base + 3])
        return Double(mantissa) * pow(10.0, Double(exponent))
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
