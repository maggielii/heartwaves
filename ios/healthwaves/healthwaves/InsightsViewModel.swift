//
//  InsightsViewModel.swift
//  healthwaves
//
//  Created by Sophia Xu on 2026-02-07.
//

import Foundation
import HealthKit
import Combine

@MainActor
final class InsightsViewModel: ObservableObject {

    @Published var blurbs: [String] = []
    @Published var isLoading: Bool = false
    @Published var errorText: String = ""

    private let apiKey: String
    private let healthStore = HKHealthStore()

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Public API
    func analyzeActiveEnergyLast28Days() {
        Task {
            isLoading = true
            errorText = ""
            blurbs = []

            do {
                let series = try await fetchActiveEnergyLast28Days()
                if series.isEmpty {
                    throw NSError(
                        domain: "Insights",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "No Active Energy data found for the last 28 days."]
                    )
                }

                let summary = summarize(series: series)
                let prompt = makePromptFunUnusualTrend(summary: summary, series: series)

                let geminiText = try await callGemini(prompt: prompt)
                let three = parseThreeBlurbsFromJSON(text: geminiText)

                if let three {
                    blurbs = [
                        "Fun fact: \(three.fun_fact)",
                        "Unusual: \(three.unusual)",
                        "Trend: \(three.trend)"
                    ]
                } else {
                    // Fallback (still matches your 3-bucket structure)
                    blurbs = [
                        "Fun fact: Your peak was \(summary.maxKcal) kcal on \(summary.maxDay).",
                        "Unusual: Your lowest day was \(summary.minKcal) kcal on \(summary.minDay).",
                        "Trend: You’re \(summary.trendNote)."
                    ]
                }

                isLoading = false
            } catch {
                isLoading = false
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - HealthKit
private extension InsightsViewModel {

    func fetchActiveEnergyLast28Days() async throws -> [(day: String, kcal: Int)] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "Insights", code: 2, userInfo: [NSLocalizedDescriptionKey: "Health data is not available on this device."])
        }

        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw NSError(domain: "Insights", code: 3, userInfo: [NSLocalizedDescriptionKey: "Active Energy type is unavailable."])
        }

        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -27, to: calendar.startOfDay(for: end)) else {
            throw NSError(domain: "Insights", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not compute date range."])
        }

        let unit = HKUnit.kilocalorie()
        let anchor = calendar.startOfDay(for: end)
        let interval = DateComponents(day: 1)

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = results else {
                    continuation.resume(returning: [])
                    return
                }

                var out: [(String, Int)] = []
                let df = DateFormatter()
                df.dateFormat = "MMM d"

                results.enumerateStatistics(from: start, to: end) { stat, _ in
                    let sum = stat.sumQuantity()?.doubleValue(for: unit) ?? 0
                    let dayLabel = df.string(from: stat.startDate)
                    out.append((dayLabel, Int(round(sum))))
                }

                continuation.resume(returning: out)
            }

            self.healthStore.execute(query)
        }
    }
}

// MARK: - Summary + Prompt
private extension InsightsViewModel {

    struct Summary {
        let totalKcal: Int
        let avgKcal: Int
        let maxKcal: Int
        let minKcal: Int
        let maxDay: String
        let minDay: String
        let trendNote: String
    }

    func summarize(series: [(day: String, kcal: Int)]) -> Summary {
        let values = series.map { $0.kcal }
        let total = values.reduce(0, +)
        let avg = Int(round(Double(total) / Double(max(values.count, 1))))

        let maxPair = series.max { $0.kcal < $1.kcal } ?? series[0]
        let minPair = series.min { $0.kcal < $1.kcal } ?? series[0]

        // Simple trend: compare last 7 avg vs prior 7 avg
        let last7 = series.suffix(7).map { $0.kcal }
        let prev7 = series.dropLast(7).suffix(7).map { $0.kcal }

        let last7Avg = last7.isEmpty ? 0 : Double(last7.reduce(0, +)) / Double(last7.count)
        let prev7Avg = prev7.isEmpty ? 0 : Double(prev7.reduce(0, +)) / Double(prev7.count)
        let delta = last7Avg - prev7Avg

        let trend: String
        if abs(delta) < 30 {
            trend = "roughly steady over the last 2 weeks"
        } else if delta > 0 {
            trend = "trending up recently"
        } else {
            trend = "trending down recently"
        }

        return Summary(
            totalKcal: total,
            avgKcal: avg,
            maxKcal: maxPair.kcal,
            minKcal: minPair.kcal,
            maxDay: maxPair.day,
            minDay: minPair.day,
            trendNote: trend
        )
    }

    func makePromptFunUnusualTrend(summary: Summary, series: [(day: String, kcal: Int)]) -> String {
        let seriesText = series.map { "\($0.day): \($0.kcal)" }.joined(separator: ", ")

        return """
        You are a playful, supportive fitness insights assistant.

        Produce EXACTLY 3 one-sentence blurbs based on Active Energy (kcal) over the last 28 days:

        1) fun_fact: a fun concrete observation (include a number/day if possible)
        2) unusual: a surprising outlier or irregular pattern you noticed (include day/amount)
        3) trend: a trend across time (up/down/steady), ideally comparing recent week vs prior week

        Constraints:
        - Each value MUST be exactly ONE sentence.
        - Max 18 words per sentence.
        - No medical advice, no diagnosis, no warnings.
        - Output ONLY valid JSON in this exact shape (no extra text):

          {"fun_fact":"...","unusual":"...","trend":"..."}

        Stats:
        - Total: \(summary.totalKcal) kcal
        - Avg/day: \(summary.avgKcal) kcal
        - Peak: \(summary.maxKcal) kcal on \(summary.maxDay)
        - Low: \(summary.minKcal) kcal on \(summary.minDay)
        - Trend note: \(summary.trendNote)

        Data (day: kcal):
        \(seriesText)

        If you output anything besides JSON, it will be rejected.
        """
    }
}

// MARK: - Gemini + JSON parsing
private extension InsightsViewModel {

    struct ThreeBlurbs: Decodable {
        let fun_fact: String
        let unusual: String
        let trend: String
    }

    func parseThreeBlurbsFromJSON(text: String) -> ThreeBlurbs? {
        func decode(_ s: String) -> ThreeBlurbs? {
            guard let data = s.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ThreeBlurbs.self, from: data)
        }

        // direct JSON
        if let direct = decode(text) { return direct }

        // extract {...} if the model wrapped it
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }

        return decode(String(text[start...end]))
    }

    func callGemini(prompt: String) async throws -> String {
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(domain: "Insights", code: 10, userInfo: [NSLocalizedDescriptionKey: "Gemini API key is missing."])
        }

        let model = "gemini-2.5-flash"
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Insights", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini URL."])
        }

        let payload: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.6,
                "maxOutputTokens": 300
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        let (respData, resp) = try await URLSession.shared.data(for: req)

        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: respData, encoding: .utf8) ?? ""
            throw NSError(domain: "Insights", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini error \(http.statusCode): \(body)"])
        }

        let json = try JSONSerialization.jsonObject(with: respData, options: [])
        guard let dict = json as? [String: Any] else {
            throw NSError(domain: "Insights", code: 12, userInfo: [NSLocalizedDescriptionKey: "Unexpected Gemini response format."])
        }

        if let candidates = dict["candidates"] as? [[String: Any]],
           let first = candidates.first,
           let content = first["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {

            let combined = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return combined.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(data: respData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
