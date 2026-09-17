import SwiftUI

struct ScaleEntryFormView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ScaleEntry) -> Void

    @State private var date = Date.now
    @State private var useImperial = false

    @State private var weightText = ""
    @State private var heightText = ""
    @State private var bmiText = ""
    @State private var bodyFatText = ""
    @State private var fatFreeWeightText = ""
    @State private var muscleMassText = ""
    @State private var boneMassText = ""
    @State private var visceralFatText = ""
    @State private var subcutaneousFatText = ""
    @State private var bmrText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date)
                    Picker("Units", selection: $useImperial) {
                        Text("Metric (kg/cm)").tag(false)
                        Text("Imperial (lb/in)").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Body measurements") {
                    numberField("Weight (\(useImperial ? "lb" : "kg"))", text: $weightText)
                    numberField("Height (\(useImperial ? "in" : "cm"))", text: $heightText)
                    numberField("BMI", text: $bmiText)
                    Button("Calculate BMI from weight & height") {
                        calculateBMI()
                    }
                    .disabled(weightKg == nil || heightCm == nil)
                }

                Section("Composition (syncs to Health)") {
                    numberField("Body fat %", text: $bodyFatText)
                    numberField("Fat-free body weight (\(useImperial ? "lb" : "kg"))", text: $fatFreeWeightText)
                    numberField("Basal metabolic rate (kcal)", text: $bmrText)
                }

                Section("Composition (this app only)") {
                    numberField("Muscle mass (\(useImperial ? "lb" : "kg"))", text: $muscleMassText)
                    numberField("Bone mass (\(useImperial ? "lb" : "kg"))", text: $boneMassText)
                    numberField("Visceral fat rating", text: $visceralFatText)
                    numberField("Subcutaneous fat %", text: $subcutaneousFatText)
                } footer: {
                    Text("Apple Health has no data type for muscle mass, bone mass, or visceral/subcutaneous fat, so these stay in this app's own log rather than a sync that would silently fail.")
                }
            }
            .navigationTitle("Log Scale Reading")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(buildEntry())
                        dismiss()
                    }
                    .disabled(isEmpty)
                }
            }
        }
    }

    private var isEmpty: Bool {
        [weightText, heightText, bmiText, bodyFatText, fatFreeWeightText, muscleMassText, boneMassText, visceralFatText, subcutaneousFatText, bmrText]
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var weightKg: Double? {
        guard let value = Double(weightText) else { return nil }
        return useImperial ? value * 0.45359237 : value
    }

    private var heightCm: Double? {
        guard let value = Double(heightText) else { return nil }
        return useImperial ? value * 2.54 : value
    }

    private func massKg(_ text: String) -> Double? {
        guard let value = Double(text) else { return nil }
        return useImperial ? value * 0.45359237 : value
    }

    private func calculateBMI() {
        guard let weight = weightKg, let height = heightCm,
              let bmi = ScaleEntry.computedBMI(weightKg: weight, heightCm: height) else { return }
        bmiText = String(format: "%.1f", bmi)
    }

    private func buildEntry() -> ScaleEntry {
        ScaleEntry(
            date: date,
            weightKg: weightKg,
            heightCm: heightCm,
            bmi: Double(bmiText),
            bodyFatPercentage: Double(bodyFatText),
            fatFreeBodyWeightKg: massKg(fatFreeWeightText),
            muscleMassKg: massKg(muscleMassText),
            boneMassKg: massKg(boneMassText),
            visceralFatRating: Double(visceralFatText),
            subcutaneousFatPercentage: Double(subcutaneousFatText),
            basalMetabolicRateKcal: Double(bmrText)
        )
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }
}
