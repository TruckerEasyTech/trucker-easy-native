import Foundation
import CoreLocation

/// Sync mínimo de wellness para Supabase (humor, check-in, correlação com visitas).
enum WellnessCloudSync {

    enum CheckinSource: String {
        case launch
        case checkup
        case horizon
    }

    static func pushDailyCheckin(
        moodStars: Int,
        sleepHours: Double? = nil,
        hadMeal: Bool? = nil,
        feltRested: Bool? = nil,
        source: CheckinSource
    ) {
        guard moodStars > 0,
              SupabaseClient.shared.isAuthenticated,
              let driverId = SupabaseClient.shared.currentDriverId else { return }

        let payload = DriverWellnessCheckinPayload(
            driver_id: driverId,
            checkin_date: isoDate(Date()),
            mood_stars: moodStars,
            stress_level: max(1, min(5, 6 - moodStars)),
            sleep_hours: sleepHours,
            had_meal: hadMeal,
            felt_rested: feltRested,
            source: source.rawValue
        )

        Task {
            do {
                try await SupabaseClient.shared.submitDriverWellnessCheckin(payload)
            } catch {
                #if DEBUG
                print("[WellnessCloud] checkin failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    static func pushTruckStopInsight(
        placeName: String,
        coordinate: CLLocationCoordinate2D,
        moodStars: Int?,
        visitAvgStars: Double,
        serviceRating: Int,
        showerRating: Int,
        foodRating: Int,
        correlationNote: String?
    ) {
        pushInsight(
            visitKind: "truck_stop",
            placeName: placeName,
            moodStars: moodStars,
            visitAvgStars: visitAvgStars,
            serviceRating: serviceRating,
            showerRating: showerRating,
            foodRating: foodRating,
            correlationNote: correlationNote,
            coordinate: coordinate
        )
    }

    static func pushFacilityInsight(
        review: FacilityReview,
        moodStars: Int?,
        visitAvgStars: Double,
        correlationNote: String?
    ) {
        let company = review.companyName ?? review.loadNumber
        pushInsight(
            visitKind: review.type == .pickup ? "pickup" : "delivery",
            placeName: company,
            moodStars: moodStars,
            visitAvgStars: visitAvgStars,
            treatmentRating: review.treatmentRating,
            bathroomRating: review.bathroomRating,
            foodAccessRating: review.foodAccessRating,
            accessRating: review.accessRating,
            correlationNote: correlationNote,
            coordinate: review.coordinate,
            loadNumber: review.loadNumber,
            companyName: review.companyName
        )
    }

    // MARK: - Private

    private static func pushInsight(
        visitKind: String,
        placeName: String,
        moodStars: Int?,
        visitAvgStars: Double,
        serviceRating: Int = 0,
        showerRating: Int = 0,
        foodRating: Int = 0,
        treatmentRating: Int = 0,
        bathroomRating: Int = 0,
        foodAccessRating: Int = 0,
        accessRating: Int = 0,
        correlationNote: String?,
        coordinate: CLLocationCoordinate2D?,
        loadNumber: String? = nil,
        companyName: String? = nil
    ) {
        guard SupabaseClient.shared.isAuthenticated,
              let driverId = SupabaseClient.shared.currentDriverId else { return }

        let payload = DriverWellnessInsightPayload(
            driver_id: driverId,
            visit_kind: visitKind,
            place_name: placeName,
            mood_stars: moodStars,
            visit_avg_stars: visitAvgStars > 0 ? visitAvgStars : nil,
            service_rating: serviceRating > 0 ? serviceRating : nil,
            shower_rating: showerRating > 0 ? showerRating : nil,
            food_rating: foodRating > 0 ? foodRating : nil,
            treatment_rating: treatmentRating > 0 ? treatmentRating : nil,
            bathroom_rating: bathroomRating > 0 ? bathroomRating : nil,
            food_access_rating: foodAccessRating > 0 ? foodAccessRating : nil,
            access_rating: accessRating > 0 ? accessRating : nil,
            correlation_note: correlationNote,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            load_number: loadNumber,
            company_name: companyName
        )

        Task {
            do {
                try await SupabaseClient.shared.submitDriverWellnessInsight(payload)
            } catch {
                #if DEBUG
                print("[WellnessCloud] insight failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
