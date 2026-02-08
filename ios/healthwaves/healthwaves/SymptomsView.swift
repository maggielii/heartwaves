import SwiftUI

struct SymptomsView: View {
    @State private var symptom: String = ""
    @State private var severity: Int = 1
    @State private var notes: String = ""
    @State private var loggedSymptoms: [(symptom: String, severity: Int, notes: String)] = []

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Log Your Symptoms")
                    .font(.largeTitle)
                    .bold()

                TextField("Symptom", text: $symptom)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Stepper(value: $severity, in: 1...10) {
                    Text("Severity: \(severity)")
                }

                TextField("Additional Notes", text: $notes)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: {
                    let newSymptom = (symptom: symptom, severity: severity, notes: notes)
                    loggedSymptoms.append(newSymptom)
                    symptom = ""
                    severity = 1
                    notes = ""
                }) {
                    Text("Log Symptom")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                List {
                    ForEach(loggedSymptoms, id: \.(\.symptom)) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.symptom)
                                .font(.headline)
                            Text("Severity: \(entry.severity)")
                                .font(.subheadline)
                            if !entry.notes.isEmpty {
                                Text(entry.notes)
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Symptoms")
        }
    }
}

struct SymptomsView_Previews: PreviewProvider {
    static var previews: some View {
        SymptomsView()
    }
}