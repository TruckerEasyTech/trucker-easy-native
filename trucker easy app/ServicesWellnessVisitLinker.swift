import Foundation
import SwiftData
import CoreLocation

/// Liga avaliações de posto/empresa ao diário de wellness do motorista (SwiftData local).
enum WellnessVisitLinker {

    @MainActor
    static func linkTruckStopReview(
        _ review: StopReview,
        stopName: String,
        coordinate: CLLocationCoordinate2D,
        modelContext: ModelContext
    ) {
        let now = Date()
        let summaryParts = ratingParts(
            service: review.serviceRating,
            shower: review.showerRating,
            food: review.foodRating
        )

        if review.foodRating > 0 {
            let foodLog = WellnessLog(
                category: .nutrition,
                date: now,
                notes: "Posto \(stopName) · comida \(review.foodRating)/5"
            )
            foodLog.mealQuality = review.foodRating
            modelContext.insert(foodLog)
        }

        let ratings = [review.serviceRating, review.showerRating, review.foodRating].filter { $0 > 0 }
        let average = averageStars(ratings)

        var visitNotes = "Posto \(stopName)"
        if !summaryParts.isEmpty { visitNotes += ": " + summaryParts.joined(separator: ", ") }
        if !review.notes.isEmpty { visitNotes += " — \(review.notes)" }

        let visitLog = WellnessLog(category: .safety, date: now, notes: visitNotes)
        if average > 0 { visitLog.stressLevel = stressFromStars(average) }
        modelContext.insert(visitLog)

        let correlation = correlateWithTodaysMood(
            modelContext: modelContext,
            placeLabel: stopName,
            visitKind: "posto",
            visitAverageStars: average,
            detailNote: review.notes
        )
        try? modelContext.save()

        let moodStars = correlation.moodStars ?? todaysMoodStars(modelContext: modelContext)
        WellnessCloudSync.pushTruckStopInsight(
            placeName: stopName,
            coordinate: coordinate,
            moodStars: moodStars,
            visitAvgStars: average,
            serviceRating: review.serviceRating,
            showerRating: review.showerRating,
            foodRating: review.foodRating,
            correlationNote: correlation.note
        )
    }

    @MainActor
    static func linkFacilityReview(_ review: FacilityReview, modelContext: ModelContext) {
        let now = Date()
        let company = review.companyName ?? review.loadNumber
        let kind = review.type == .pickup ? "carregamento" : "entrega"

        let summaryParts = ratingParts(
            food: review.foodAccessRating,
            treatment: review.treatmentRating,
            bathroom: review.bathroomRating,
            access: review.accessRating
        )

        if review.foodAccessRating > 0 {
            let foodLog = WellnessLog(
                category: .nutrition,
                date: now,
                notes: "\(kind.capitalized) \(company) · comida/lanche \(review.foodAccessRating)/5"
            )
            foodLog.mealQuality = review.foodAccessRating
            modelContext.insert(foodLog)
        }

        let ratings = [
            review.treatmentRating,
            review.bathroomRating,
            review.foodAccessRating,
            review.accessRating
        ].filter { $0 > 0 }
        let average = averageStars(ratings)

        var visitNotes = "\(kind.capitalized) \(company)"
        if !summaryParts.isEmpty { visitNotes += ": " + summaryParts.joined(separator: ", ") }
        if let wait = review.waitMinutes, wait > 0 { visitNotes += " · espera \(wait) min" }
        if !review.notes.isEmpty { visitNotes += " — \(review.notes)" }

        let visitLog = WellnessLog(category: .safety, date: now, notes: visitNotes)
        if average > 0 { visitLog.stressLevel = stressFromStars(average) }
        modelContext.insert(visitLog)

        if review.treatmentRating > 0 {
            let treatmentLog = WellnessLog(
                category: .mental,
                date: now,
                notes: "Empresa \(company) · atendimento \(review.treatmentRating)/5"
            )
            treatmentLog.stressLevel = stressFromStars(Double(review.treatmentRating))
            modelContext.insert(treatmentLog)
        }

        let correlation = correlateWithTodaysMood(
            modelContext: modelContext,
            placeLabel: company,
            visitKind: kind,
            visitAverageStars: average,
            detailNote: review.notes
        )
        try? modelContext.save()

        let moodStars = correlation.moodStars ?? todaysMoodStars(modelContext: modelContext)
        WellnessCloudSync.pushFacilityInsight(
            review: review,
            moodStars: moodStars,
            visitAvgStars: average,
            correlationNote: correlation.note
        )
    }

    // MARK: - Mood correlation

    private struct MoodCorrelation {
        let moodStars: Int?
        let note: String?
    }

    @MainActor
    private static func correlateWithTodaysMood(
        modelContext: ModelContext,
        placeLabel: String,
        visitKind: String,
        visitAverageStars: Double,
        detailNote: String
    ) -> MoodCorrelation {
        guard visitAverageStars > 0,
              let moodLog = todaysPrimaryMoodLog(modelContext: modelContext),
              let stress = moodLog.stressLevel else {
            return MoodCorrelation(moodStars: nil, note: nil)
        }

        let moodStars = 6 - stress
        let visitLow = visitAverageStars <= 2.5
        let visitHigh = visitAverageStars >= 4.0
        let moodLow = moodStars <= 2
        let moodHigh = moodStars >= 4

        let correlationNote: String?
        if visitLow && moodLow {
            correlationNote = "Dia difícil: humor \(moodStars)/5 e \(visitKind) \(placeLabel) \(formattedStars(visitAverageStars))/5."
        } else if visitHigh && moodHigh {
            correlationNote = "Dia positivo: humor \(moodStars)/5 e \(visitKind) \(placeLabel) \(formattedStars(visitAverageStars))/5."
        } else if visitLow && moodHigh {
            correlationNote = "Humor ok (\(moodStars)/5), mas \(visitKind) \(placeLabel) foi ruim (\(formattedStars(visitAverageStars))/5)."
        } else if visitHigh && moodLow {
            correlationNote = "Humor baixo (\(moodStars)/5), mas \(visitKind) \(placeLabel) foi bom (\(formattedStars(visitAverageStars))/5)."
        } else {
            correlationNote = nil
        }

        guard let correlationNote else {
            return MoodCorrelation(moodStars: moodStars, note: nil)
        }

        appendNote(correlationNote, to: moodLog)
        if !detailNote.isEmpty, !moodLog.notes.contains(detailNote) {
            appendNote(detailNote, to: moodLog)
        }

        let insight = WellnessLog(category: .mental, date: Date(), notes: "Insight · \(correlationNote)")
        insight.stressLevel = stress
        modelContext.insert(insight)

        return MoodCorrelation(moodStars: moodStars, note: correlationNote)
    }

    @MainActor
    private static func todaysMoodStars(modelContext: ModelContext) -> Int? {
        guard let stress = todaysPrimaryMoodLog(modelContext: modelContext)?.stressLevel else { return nil }
        return 6 - stress
    }

    @MainActor
    private static func todaysPrimaryMoodLog(modelContext: ModelContext) -> WellnessLog? {
        var descriptor = FetchDescriptor<WellnessLog>(
            sortBy: [SortDescriptor(\WellnessLog.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        guard let logs = try? modelContext.fetch(descriptor) else { return nil }
        return logs.first { $0.date.isToday && $0.category == .mental && $0.stressLevel != nil }
    }

    // MARK: - Helpers

    private static func ratingParts(
        service: Int = 0,
        shower: Int = 0,
        food: Int = 0,
        treatment: Int = 0,
        bathroom: Int = 0,
        access: Int = 0
    ) -> [String] {
        var parts: [String] = []
        if service > 0 { parts.append("atendimento \(service)/5") }
        if shower > 0 { parts.append("banheiro \(shower)/5") }
        if food > 0 { parts.append("comida \(food)/5") }
        if treatment > 0 { parts.append("tratamento \(treatment)/5") }
        if bathroom > 0 { parts.append("banheiro \(bathroom)/5") }
        if access > 0 { parts.append("acesso \(access)/5") }
        return parts
    }

    private static func averageStars(_ ratings: [Int]) -> Double {
        guard !ratings.isEmpty else { return 0 }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    /// stressLevel 1 = confortável, 5 = estressante (inverso das estrelas).
    private static func stressFromStars(_ stars: Double) -> Int {
        max(1, min(5, Int(round(6.0 - stars))))
    }

    private static func formattedStars(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func appendNote(_ note: String, to log: WellnessLog) {
        if log.notes.isEmpty {
            log.notes = note
        } else if !log.notes.contains(note) {
            log.notes += " · \(note)"
        }
    }
}
