import SwiftUI
import HealthKit

struct ContentView: View {
    private let hk = HealthKitManager()

    @State private var status = "Not connected"
    @State private var stepsText = "--"
    @State private var distanceText = "--"
    @State private var energyText = "--"

    var body: some View {
        VStack(spacing: 16) {
            Text(status)
            Text("Today’s steps: \(stepsText)")
                .font(.title2)
            Text("Today’s distance: \(distanceText)")
                .font(.title2)
            Text("Today’s acgive energy: \(energyText)")
                .font(.title2)

            Button("Connect Health") {
                hk.requestAuthorization { success, message in
                    status = success ? "✅ Authorized" : "❌ Not authorized: \(message)"
                    if success {
                        loadSteps()
                        loadDistance()
                        loadActiveEnergy()
                    }
                }
            }
            Button("Refresh Steps") {
                loadSteps()
                loadDistance()
                loadActiveEnergy()
            }
        }
        .padding()
    }

    private func loadSteps() {
        hk.fetchTodayGeneral(id: .stepCount, unit: .count(), completion: { steps, error in
            if let error = error {
                status = "❌ Step fetch failed: \(error)"
                stepsText = "--"
            } else {
                status = "✅ Steps loaded"
                stepsText = String(Int(steps))
            }
        
        }
        )
    }
    
    private func loadDistance() {
        hk.fetchTodayGeneral(id: .distanceWalkingRunning, unit: .meter(), completion: { distance, error in
            if let error = error {
                status = "❌ Step fetch failed: \(error)"
                distanceText = "--"
            } else {
                status = "✅ Steps loaded"
                distanceText = String(Int(distance))
            }
        
        }
        )
    }
    
    private func loadActiveEnergy() {
        hk.fetchTodayGeneral(id: .activeEnergyBurned, unit: .kilocalorie(), completion: { energy, error in
            if let error = error {
                status = "❌ Step fetch failed: \(error)"
                energyText = "--"
            } else {
                status = "✅ Steps loaded"
                energyText = String(Int(energy))
            }
        
        }
        )
    }
}
