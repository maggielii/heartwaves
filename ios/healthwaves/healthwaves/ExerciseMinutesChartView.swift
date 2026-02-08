import SwiftUI
import Charts
import HealthKit

struct ExerciseMinutesChartView: View {
    private let hk = HealthKitManager()

    @State private var dataPoints: [HealthDataPoint] = []
    @State private var avgMinutes: Double = 0
    @State private var totalMinutes: Double = 0

    // Optional: allow paging like your Sleep view
    @State private var weeksBack: Int = 0   // 0 = this week, 1 = last week...

    private let accent = Color(red: 1, green: 0, blue: 1.0)

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {

                // Header
                HStack {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Exercise Minutes")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.primary)

                        Text(weekRangeText)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .animation(.easeInOut(duration: 0.25), value: weeksBack)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top)

                // Week navigation
                HStack(spacing: 16) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { weeksBack += 1 }
                        loadExerciseMinutes()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(accent)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(accent.opacity(0.12)))
                    }

                    Text(weeksBack == 0 ? "This Week" : "\(weeksBack) week\(weeksBack == 1 ? "" : "s") ago")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .animation(.easeInOut(duration: 0.25), value: weeksBack)

                    Button {
                        guard weeksBack > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.25)) { weeksBack -= 1 }
                        loadExerciseMinutes()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(weeksBack > 0 ? accent : .gray.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle().fill(weeksBack > 0 ? accent.opacity(0.12) : Color.gray.opacity(0.06))
                            )
                    }
                    .disabled(weeksBack == 0)
                }
                .padding(.horizontal)

                // Stats row
                HStack(spacing: 16) {
                    statCard(title: "avg / day", value: avgText)
                    statCard(title: "total", value: totalText)
                }
                .padding(.horizontal)

                // Chart
                if dataPoints.isEmpty {
                    Text("No exercise minutes available")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(height: 220)
                        .transition(.opacity)
                } else {
                    Chart {
                        // Average line
                        RuleMark(y: .value("Average", avgMinutes))
                            .foregroundStyle(accent.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        // Area + line
                        ForEach(dataPoints) { point in
                            AreaMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Minutes", point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [accent.opacity(0.55), accent.opacity(0.08)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Minutes", point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                            .foregroundStyle(accent)

                            PointMark(
                                x: .value("Day", point.date, unit: .day),
                                y: .value("Minutes", point.value)
                            )
                            .symbolSize(30)
                            .foregroundStyle(accent.opacity(0.9))
                        }
                    }
                    .chartXScale(domain: weekDomain)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                            AxisTick().foregroundStyle(Color.secondary.opacity(0.25))
                            AxisValueLabel {
                                if let y = value.as(Double.self) {
                                    Text("\(Int(y))")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 1)) { value in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.04))
                            AxisTick().foregroundStyle(Color.secondary.opacity(0.25))
                            AxisValueLabel {
                                if let d = value.as(Date.self) {
                                    Text(dayLabel(d))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 240)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                // Refresh
                Button {
                    loadExerciseMinutes()
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
                            .fill(accent.opacity(0.12))
                    )
                }
                .padding(.bottom)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
            )
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .onAppear {
            // Make sure HK auth has been requested somewhere before this.
            loadExerciseMinutes()
        }
    }

    // MARK: - UI helpers

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE" // Mon Tue...
        return f.string(from: date)
    }

    // MARK: - Date helpers

    private var weekRangeText: String {
        let cal = Calendar.current
        let startOfCurrentWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let weekStart = cal.date(byAdding: .weekOfYear, value: -weeksBack, to: startOfCurrentWeek)!
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!

        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: weekStart)) - \(f.string(from: weekEnd))"
    }

    private var weekDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let startOfCurrentWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let weekStart = cal.date(byAdding: .weekOfYear, value: -weeksBack, to: startOfCurrentWeek)!
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)! // exclusive end
        return weekStart...weekEnd
    }

    private var avgText: String {
        if dataPoints.isEmpty { return "--" }
        if avgMinutes >= 100 { return "\(Int(avgMinutes)) min" }
        return String(format: "%.0f min", avgMinutes)
    }

    private var totalText: String {
        if dataPoints.isEmpty { return "--" }
        if totalMinutes >= 1000 { return "\(Int(totalMinutes)) min" }
        return String(format: "%.0f min", totalMinutes)
    }

    // MARK: - Data

    private func loadExerciseMinutes() {
        let cal = Calendar.current
        let startOfCurrentWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        let weekStart = cal.date(byAdding: .weekOfYear, value: -weeksBack, to: startOfCurrentWeek)!
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)! // exclusive end

        withAnimation(.easeOut(duration: 0.15)) {
            dataPoints = []
            avgMinutes = 0
            totalMinutes = 0
        }

        hk.fetchSamples(
            id: .appleExerciseTime,
            unit: .minute(),
            startDate: weekStart,
            endDate: weekEnd
        ) { points, error in
            if let error = error {
                print("Exercise fetch error: \(error)")
                return
            }

            // Sort just in case
            let sorted = points.sorted { $0.date < $1.date }

            let total = sorted.reduce(0.0) { $0 + $1.value }
            let avg = sorted.isEmpty ? 0.0 : total / Double(sorted.count)

            withAnimation(.easeInOut(duration: 0.35).delay(0.05)) {
                dataPoints = sorted
                totalMinutes = total
                avgMinutes = avg
            }
        }
    }
}
