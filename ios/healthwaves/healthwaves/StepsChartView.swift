import SwiftUI
import HealthKit
import Charts

struct StepsChartView: View {
    private let hk = HealthKitManager()
    @State private var dataPoints: [HealthDataPoint] = []
    @State private var totalSteps: Int = 0
    @State private var weeksBack: Int = 0  // 0 = current week, 1 = last week, etc.
    
    var body: some View {
        VStack(spacing: 20) {
            // Widget-style card
            VStack(spacing: 16) {
                // Header with navigation
                HStack {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.pink)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Steps")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.primary)
                        Text(weekRangeText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .animation(.easeInOut(duration: 0.3), value: weeksBack)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Week navigation buttons
                HStack(spacing: 16) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            weeksBack += 1
                        }
                        loadStepsData()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.pink)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.pink.opacity(0.1))
                            )
                    }
                    
                    Text(weeksBack == 0 ? "This Week" : "\(weeksBack) week\(weeksBack == 1 ? "" : "s") ago")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.3), value: weeksBack)
                    
                    Button(action: {
                        if weeksBack > 0 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                weeksBack -= 1
                            }
                            loadStepsData()
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(weeksBack > 0 ? .pink : .gray.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(weeksBack > 0 ? Color.pink.opacity(0.1) : Color.gray.opacity(0.05))
                            )
                    }
                    .disabled(weeksBack == 0)
                }
                .padding(.horizontal)
                
                // Total steps stat
                VStack(spacing: 4) {
                    Text("\(totalSteps)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.pink)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: totalSteps)
                    Text("total steps")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                
                // Chart with animation
                if dataPoints.isEmpty {
                    Text("No data available")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                        .transition(.opacity)
                } else {
                    Chart(dataPoints) { point in
                        BarMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Steps", point.value)
                        )
                        .foregroundStyle(.pink)
                    }
                    .frame(height: 220)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                // Refresh button
                Button(action: {
                    loadStepsData()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Refresh")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.pink)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.pink.opacity(0.1))
                    )
                }
                .padding(.bottom)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.top)
        .onAppear {
            loadStepsData()
        }
    }
    
    private var weekRangeText: String {
        let calendar = Calendar.current
        let endDate = Date()
        let startOfCurrentWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: endDate))!
        
        let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: startOfCurrentWeek)!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
    }
    
    private func loadStepsData() {
        let calendar = Calendar.current
        let now = Date()
        let startOfCurrentWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        
        let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: startOfCurrentWeek)!
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
        
        // Fade out current data
        withAnimation(.easeOut(duration: 0.15)) {
            dataPoints = []
        }
        
        hk.fetchSamples(
            id: .stepCount,
            unit: HKUnit.count(),
            startDate: weekStart,
            endDate: weekEnd
        ) { points, error in
            if let error = error {
                print("Steps fetch error: \(error)")
            } else {
                // Fade in new data
                withAnimation(.easeInOut(duration: 0.5).delay(0.15)) {
                    dataPoints = points
                    totalSteps = Int(points.map { $0.value }.reduce(0, +))
                }
            }
        }
    }
}
