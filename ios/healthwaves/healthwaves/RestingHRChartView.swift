import SwiftUI
import HealthKit
import Charts

struct RestingHRChartView: View {

    private let hk = HealthKitManager()

    @State private var dataPoints: [HealthDataPoint] = []
    @State private var avgBPM: Double = 0
    @State private var weeksBack: Int = 0

    private let accent = Color(red: 1, green: 0, blue: 0.1)
    var body: some View {
        
        
        VStack(spacing: 20) {
            VStack(spacing: 16) {

                // Header
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Resting Heart Rate")
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

                // Week navigation
                HStack(spacing: 16) {

                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            weeksBack += 1
                        }
                        loadRestingHR()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(accent)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle().fill(accent.opacity(0.1))
                            )
                    }

                    Text(weeksBack == 0 ? "This Week" : "\(weeksBack) week\(weeksBack == 1 ? "" : "s") ago")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.3), value: weeksBack)

                    Button {
                        if weeksBack > 0 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                weeksBack -= 1
                            }
                            loadRestingHR()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(weeksBack > 0 ? accent : .gray.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle().fill(weeksBack > 0 ? accent.opacity(0.1) : Color.gray.opacity(0.05))
                            )
                    }
                    .disabled(weeksBack == 0)
                }
                .padding(.horizontal)

                // Weekly average stat
                VStack(spacing: 4) {
                    Text(avgBPMText)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(accent)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: avgBPM)

                    Text("avg bpm")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)

                // Chart
                if dataPoints.isEmpty {
                    Text("No data available")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(height: 200)
                        .transition(.opacity)
                } else {
                    Chart {
                        // Soft fill
                        ForEach(dataPoints) { point in
                            AreaMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("BPM", point.value)
                            )
                            .foregroundStyle(accent.opacity(0.12))
                            .interpolationMethod(.catmullRom)
                        }

                        // Line
                        ForEach(dataPoints) { point in
                            LineMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("BPM", point.value)
                            )
                            .foregroundStyle(accent)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)
                        }

                        // Points
                        ForEach(dataPoints) { point in
                            PointMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("BPM", point.value)
                            )
                            .foregroundStyle(accent)
                            .symbolSize(30)
                        }
                    }
                    // Don’t force a 0 baseline for BPM; make it readable
                    .chartYScale(domain: yDomain)
                    .frame(height: 220)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Refresh
                Button {
                    loadRestingHR()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Refresh")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(accent)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(accent.opacity(0.1))
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
        .onAppear { loadRestingHR() }
    }

    // MARK: - Formatting / Scale

    private var avgBPMText: String {
        avgBPM == 0 ? "--" : String(format: "%.0f", avgBPM)
    }

    // Avoid “flat on the ground”: don’t force 0 baseline for BPM
    private var yDomain: ClosedRange<Double> {
        let values = dataPoints.map { $0.value }
        guard let minV = values.min(), let maxV = values.max() else { return 40...120 }
        let spread = max(6, (maxV - minV))
        let pad = spread * 0.35
        return (minV - pad)...(maxV + pad)
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

    // MARK: - Loading (daily averages using HKStatisticsCollectionQuery)

    private func loadRestingHR() {
        let calendar = Calendar.current
        let now = Date()
        let startOfCurrentWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

        let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: startOfCurrentWeek)!
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        // Fade out
        withAnimation(.easeOut(duration: 0.15)) {
            dataPoints = []
        }

        hk.fetchDailyQuantity(
            id: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: HKUnit.minute()),
            startDate: weekStart,
            endDate: weekEnd,
            options: .discreteAverage
        ) { points, error in
            if let error = error {
                print("Resting HR fetch error: \(error)")
                return
            }

            withAnimation(.easeInOut(duration: 0.5).delay(0.15)) {
                // Optional: drop 0 days if your chart looks weird due to missing data
                dataPoints = points.filter { $0.value > 0 }

                let vals = dataPoints.map { $0.value }
                avgBPM = vals.isEmpty ? 0 : (vals.reduce(0, +) / Double(vals.count))
            }
        }
    }
}
