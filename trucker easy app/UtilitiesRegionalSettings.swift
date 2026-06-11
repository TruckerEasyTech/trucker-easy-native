import Foundation
import SwiftUI

// MARK: - Global HOS Rules (Hours of Service per country/region)
// Safety-critical: these limits protect driver lives worldwide
struct HOSRules {
    let regionName: String
    let authority: String           // Regulatory body
    let maxDrivingHours: Double     // Max consecutive driving hours
    let serviceWindowHours: Double  // Total on-duty window
    let mandatoryBreakAfterHours: Double  // Break required after X hours
    let mandatoryBreakMinutes: Int  // Break duration in minutes
    let restBetweenShiftsHours: Double   // Minimum rest between shifts
    let weeklyHoursLimit: Int       // Max hours in 7 days
    let extendedWeeklyHours: Int    // Max hours in 8 days (if applicable)
    let weeklyResetHours: Double    // Hours of rest for weekly reset
    let weightLimitTonnes: Double   // Max gross vehicle weight (tonnes)
    let weightLimitLbs: Double      // Max gross vehicle weight (lbs)
    let maxHeightMeters: Double     // Max vehicle height (meters)
    let maxLengthMeters: Double     // Max vehicle length (meters)
    let notes: [String]             // Additional safety notes

    // MARK: - Preset rules per region
    static let usa = HOSRules(
        regionName: "USA (FMCSA)",
        authority: "FMCSA - Federal Motor Carrier Safety Administration",
        maxDrivingHours: 11,
        serviceWindowHours: 14,
        mandatoryBreakAfterHours: 8,
        mandatoryBreakMinutes: 30,
        restBetweenShiftsHours: 10,
        weeklyHoursLimit: 60,
        extendedWeeklyHours: 70,
        weeklyResetHours: 34,
        weightLimitTonnes: 36.29,
        weightLimitLbs: 80000,
        maxHeightMeters: 4.11,
        maxLengthMeters: 16.76,
        notes: [
            "11-hour driving limit within 14-hour window",
            "30-min break required after 8 hours on duty",
            "10 consecutive hours off duty required",
            "60/70-hour weekly limit (7/8 days)",
            "34-hour restart resets weekly hours",
            "ELD (Electronic Logging Device) mandatory"
        ]
    )

    static let canada = HOSRules(
        regionName: "Canada (TC)",
        authority: "Transport Canada",
        maxDrivingHours: 13,
        serviceWindowHours: 16,
        mandatoryBreakAfterHours: 8,
        mandatoryBreakMinutes: 30,
        restBetweenShiftsHours: 8,
        weeklyHoursLimit: 70,
        extendedWeeklyHours: 120,
        weeklyResetHours: 36,
        weightLimitTonnes: 63.5,
        weightLimitLbs: 139994,
        maxHeightMeters: 4.15,
        maxLengthMeters: 25.0,
        notes: [
            "13-hour driving limit within 16-hour window",
            "30-min break after 8 hours driving",
            "8 hours off duty between shifts",
            "70-hour limit in 7 days (south of 60°N)",
            "120-hour limit in 14 days (north of 60°N)",
            "ELD mandatory (since Jan 1, 2023)"
        ]
    )

    static let brazil = HOSRules(
        regionName: "Brasil (ANTT/CLT)",
        authority: "ANTT - Agência Nacional de Transportes Terrestres",
        maxDrivingHours: 8,
        serviceWindowHours: 11,
        mandatoryBreakAfterHours: 4,
        mandatoryBreakMinutes: 30,
        restBetweenShiftsHours: 11,
        weeklyHoursLimit: 44,
        extendedWeeklyHours: 48,
        weeklyResetHours: 24,
        weightLimitTonnes: 57.0,
        weightLimitLbs: 125663,
        maxHeightMeters: 4.40,
        maxLengthMeters: 30.0,
        notes: [
            "Máximo 8h de direção contínua por dia (CLT Art. 235-C)",
            "Pausa obrigatória de 30min a cada 4h de direção",
            "11h de descanso mínimo entre jornadas",
            "Limite de 44h semanais (CLT) + horas extras com adicional",
            "Jornada diária máxima: 11h (incluindo carga/descarga)",
            "Tacógrafo obrigatório para veículos > 10 toneladas",
            "Peso bruto máximo: 57 toneladas (combinações especiais)"
        ]
    )

    static let mexico = HOSRules(
        regionName: "México (SCT)",
        authority: "SCT - Secretaría de Comunicaciones y Transportes",
        maxDrivingHours: 10,
        serviceWindowHours: 14,
        mandatoryBreakAfterHours: 5,
        mandatoryBreakMinutes: 30,
        restBetweenShiftsHours: 8,
        weeklyHoursLimit: 60,
        extendedWeeklyHours: 70,
        weeklyResetHours: 34,
        weightLimitTonnes: 66.5,
        weightLimitLbs: 146608,
        maxHeightMeters: 4.25,
        maxLengthMeters: 31.0,
        notes: [
            "Máximo 10 horas de conducción continua",
            "Descanso de 30 min cada 5 horas al volante",
            "8 horas mínimo de descanso entre turnos",
            "Límite semanal: 60-70 horas en 7-8 días",
            "Peso bruto máximo: 66.5 toneladas (convoy)",
            "Velocidad máxima en carretera: 90 km/h"
        ]
    )

    static let europe = HOSRules(
        regionName: "EU (EC 561/2006)",
        authority: "European Commission Regulation EC 561/2006",
        maxDrivingHours: 9,
        serviceWindowHours: 13,
        mandatoryBreakAfterHours: 4.5,
        mandatoryBreakMinutes: 45,
        restBetweenShiftsHours: 11,
        weeklyHoursLimit: 56,
        extendedWeeklyHours: 90,
        weeklyResetHours: 45,
        weightLimitTonnes: 44.0,
        weightLimitLbs: 97002,
        maxHeightMeters: 4.0,
        maxLengthMeters: 18.75,
        notes: [
            "Max 9h driving/day (extendable to 10h twice/week)",
            "45-min break after 4.5h (can split: 15+30 min)",
            "11h daily rest (can reduce to 9h 3x/week)",
            "Weekly limit: 56h; fortnightly: 90h",
            "45h weekly rest required every 2 weeks",
            "Digital tachograph mandatory",
            "Max speed with limiter: 90 km/h"
        ]
    )

    static let australia = HOSRules(
        regionName: "Australia (NHVR)",
        authority: "NHVR - National Heavy Vehicle Regulator",
        maxDrivingHours: 12,
        serviceWindowHours: 14,
        mandatoryBreakAfterHours: 5.25,
        mandatoryBreakMinutes: 30,
        restBetweenShiftsHours: 7,
        weeklyHoursLimit: 72,
        extendedWeeklyHours: 144,
        weeklyResetHours: 24,
        weightLimitTonnes: 42.5,
        weightLimitLbs: 93696,
        maxHeightMeters: 4.30,
        maxLengthMeters: 19.0,
        notes: [
            "Standard Hours: max 12h work, max 12h driving in 24h",
            "30-min break after 5.25h continuous driving",
            "7h stationary rest minimum in 24h",
            "BFM Option: 14h work window available",
            "Advanced Fatigue Management available",
            "NHVL (National Heavy Vehicle Law) applies",
            "PBS vehicles may have different limits"
        ]
    )

    static let uk = HOSRules(
        regionName: "UK (DVSA)",
        authority: "DVSA - Driver & Vehicle Standards Agency",
        maxDrivingHours: 9,
        serviceWindowHours: 13,
        mandatoryBreakAfterHours: 4.5,
        mandatoryBreakMinutes: 45,
        restBetweenShiftsHours: 11,
        weeklyHoursLimit: 56,
        extendedWeeklyHours: 90,
        weeklyResetHours: 45,
        weightLimitTonnes: 44.0,
        weightLimitLbs: 97002,
        maxHeightMeters: 4.0,
        maxLengthMeters: 18.75,
        notes: [
            "EU rules retained post-Brexit (EC 561/2006)",
            "Max 9h driving/day (10h twice/week)",
            "45-min break after 4.5h driving",
            "11h daily rest (can reduce to 9h 3x/week)",
            "Weekly: 56h; fortnightly: 90h",
            "Digital tachograph mandatory",
            "Working Time Regulations also apply (48h avg)"
        ]
    )
}

// MARK: - App Language Support
enum AppLanguage: String, CaseIterable, Identifiable {
    case english      = "English"
    case portuguese   = "Português"
    case spanish      = "Español"
    case spanishLatam = "Español Latino"
    case french       = "Français"
    case german       = "Deutsch"
    case hindi        = "हिंदी"
    case arabic       = "العربية"
    case russian      = "Русский"
    case polish       = "Polski"

    var id: String { rawValue }

    var code: String {
        switch self {
        case .english:      return "en"
        case .portuguese:   return "pt-BR"
        case .spanish:      return "es-ES"
        case .spanishLatam: return "es-419"
        case .french:       return "fr"
        case .german:       return "de"
        case .hindi:        return "hi"
        case .arabic:       return "ar"
        case .russian:      return "ru"
        case .polish:       return "pl"
        }
    }

    /// Native language name shown in UI
    var nativeName: String {
        switch self {
        case .english:      return "English"
        case .portuguese:   return "Português (BR)"
        case .spanish:      return "Español (EU)"
        case .spanishLatam: return "Español (Latino)"
        case .french:       return "Français"
        case .german:       return "Deutsch"
        case .hindi:        return "हिंदी"
        case .arabic:       return "العربية"
        case .russian:      return "Русский"
        case .polish:       return "Polski"
        }
    }

    /// isRTL — right-to-left languages
    var isRTL: Bool { self == .arabic }

    var flagEmoji: String {
        switch self {
        case .english:      return "🇺🇸"
        case .portuguese:   return "🇧🇷"
        case .spanish:      return "🇪🇸"
        case .spanishLatam: return "🇲🇽"
        case .french:       return "🇫🇷"
        case .german:       return "🇩🇪"
        case .hindi:        return "🇮🇳"
        case .arabic:       return "🇸🇦"
        case .russian:      return "🇷🇺"
        case .polish:       return "🇵🇱"
        }
    }

    // MARK: - Localized UI strings
    // Tab labels
    var tabHorizon: String {
        switch self {
        case .english:      return "My Horizon"
        case .portuguese:   return "Meu Horizonte"
        case .spanish:      return "Mi Horizonte"
        case .spanishLatam: return "Mi Horizonte"
        case .french:       return "Mon Horizon"
        case .german:       return "Mein Horizont"
        case .hindi:        return "मेरा क्षितिज"
        case .arabic:       return "أفقي"
        case .russian:      return "Мой Горизонт"
        case .polish:       return "Mój Horyzont"
        }
    }

    var tabCheckup: String {
        switch self {
        case .english:      return "My Check-up"
        case .portuguese:   return "Meu Check-up"
        case .spanish:      return "Mi Chequeo"
        case .spanishLatam: return "Mi Chequeo"
        case .french:       return "Mon Bilan"
        case .german:       return "Mein Check-up"
        case .hindi:        return "मेरी जाँच"
        case .arabic:       return "فحصي"
        case .russian:      return "Моё Здоровье"
        case .polish:       return "Moje Zdrowie"
        }
    }

    var tabCabin: String {
        switch self {
        case .english:      return "My Cabin"
        case .portuguese:   return "Minha Cabine"
        case .spanish:      return "Mi Cabina"
        case .spanishLatam: return "Mi Cabina"
        case .french:       return "Ma Cabine"
        case .german:       return "Meine Kabine"
        case .hindi:        return "मेरी कैबिन"
        case .arabic:       return "كابينتي"
        case .russian:      return "Моя Кабина"
        case .polish:       return "Moja Kabina"
        }
    }

    var tabRoadTalk: String {
        switch self {
        case .english:      return "Road Talk"
        case .portuguese:   return "Papo de Estrada"
        case .spanish:      return "Charla de Ruta"
        case .spanishLatam: return "Charla de Ruta"
        case .french:       return "Route Talk"
        case .german:       return "Straßentalk"
        case .hindi:        return "रोड टॉक"
        case .arabic:       return "حديث الطريق"
        case .russian:      return "Разговор о Дороге"
        case .polish:       return "Rozmowy Drogowe"
        }
    }

    var tabProfile: String {
        switch self {
        case .english:      return "Profile"
        case .portuguese:   return "Perfil"
        case .spanish:      return "Perfil"
        case .spanishLatam: return "Perfil"
        case .french:       return "Profil"
        case .german:       return "Profil"
        case .hindi:        return "प्रोफ़ाइल"
        case .arabic:       return "الملف"
        case .russian:      return "Профиль"
        case .polish:       return "Profil"
        }
    }

    // MARK: - Nearby category labels (icon label under map sidebar)
    // NOTE: road sign names stay in English always for safety
    var categoryFuel: String {
        switch self {
        case .english:      return "Fuel"
        case .portuguese:   return "Diesel"
        case .spanish:      return "Diésel"
        case .spanishLatam: return "Diésel"
        case .french:       return "Gazole"
        case .german:       return "Diesel"
        case .hindi:        return "डीजल"
        case .arabic:       return "وقود"
        case .russian:      return "Топливо"
        case .polish:       return "Paliwo"
        }
    }

    var categoryParking: String {
        switch self {
        case .english:      return "Parking"
        case .portuguese:   return "Estac."
        case .spanish:      return "Parqueo"
        case .spanishLatam: return "Parqueo"
        case .french:       return "Parking"
        case .german:       return "Parken"
        case .hindi:        return "पार्किंग"
        case .arabic:       return "موقف"
        case .russian:      return "Парковка"
        case .polish:       return "Parking"
        }
    }

    var categoryRest: String {
        switch self {
        case .english:      return "Rest"
        case .portuguese:   return "Descanso"
        case .spanish:      return "Descanso"
        case .spanishLatam: return "Descanso"
        case .french:       return "Repos"
        case .german:       return "Ruhe"
        case .hindi:        return "आराम"
        case .arabic:       return "راحة"
        case .russian:      return "Отдых"
        case .polish:       return "Odpocz."
        }
    }

    var categoryFood: String {
        switch self {
        case .english:      return "Food"
        case .portuguese:   return "Comida"
        case .spanish:      return "Comida"
        case .spanishLatam: return "Comida"
        case .french:       return "Nourriture"
        case .german:       return "Essen"
        case .hindi:        return "खाना"
        case .arabic:       return "طعام"
        case .russian:      return "Еда"
        case .polish:       return "Jedzenie"
        }
    }

    var categoryRepair: String {
        switch self {
        case .english:      return "Repair"
        case .portuguese:   return "Reparo"
        case .spanish:      return "Taller"
        case .spanishLatam: return "Taller"
        case .french:       return "Atelier"
        case .german:       return "Werkstatt"
        case .hindi:        return "मरम्मत"
        case .arabic:       return "ورشة"
        case .russian:      return "Ремонт"
        case .polish:       return "Naprawa"
        }
    }

    var categoryWash: String {
        switch self {
        case .english:      return "Wash"
        case .portuguese:   return "Lavagem"
        case .spanish:      return "Lavado"
        case .spanishLatam: return "Lavado"
        case .french:       return "Lavage"
        case .german:       return "Waschanlage"
        case .hindi:        return "धुलाई"
        case .arabic:       return "غسيل"
        case .russian:      return "Мойка"
        case .polish:       return "Myjnia"
        }
    }

    var categoryShower: String {
        switch self {
        case .english:      return "Showers"
        case .portuguese:   return "Ducha"
        case .spanish:      return "Duchas"
        case .spanishLatam: return "Duchas"
        case .french:       return "Douches"
        case .german:       return "Duschen"
        case .hindi:        return "शॉवर"
        case .arabic:       return "حمامات"
        case .russian:      return "Душ"
        case .polish:       return "Prysznice"
        }
    }

    // MARK: - Truck Stop Info labels
    var dieselPriceLabel: String {
        switch self {
        case .english:      return "Diesel Price"
        case .portuguese:   return "Preço do Diesel"
        case .spanish:      return "Precio Diésel"
        case .spanishLatam: return "Precio Diésel"
        case .french:       return "Prix du Gazole"
        case .german:       return "Dieselpreis"
        case .hindi:        return "डीजल मूल्य"
        case .arabic:       return "سعر الديزل"
        case .russian:      return "Цена дизеля"
        case .polish:       return "Cena Diesla"
        }
    }

    var cheapestNearbyLabel: String {
        switch self {
        case .english:      return "Cheapest Nearby"
        case .portuguese:   return "Mais Barato Perto"
        case .spanish:      return "Más Barato Cerca"
        case .spanishLatam: return "Más Barato Cerca"
        case .french:       return "Moins Cher à Proximité"
        case .german:       return "Günstigste in der Nähe"
        case .hindi:        return "नजदीक सबसे सस्ता"
        case .arabic:       return "أرخص قريب"
        case .russian:      return "Дешевле рядом"
        case .polish:       return "Najtańszy w pobliżu"
        }
    }

    var parkingAvailableLabel: String {
        switch self {
        case .english:      return "Parking Available"
        case .portuguese:   return "Vagas Disponíveis"
        case .spanish:      return "Estacionamiento Libre"
        case .spanishLatam: return "Estacionamiento Libre"
        case .french:       return "Places Disponibles"
        case .german:       return "Parkplätze Frei"
        case .hindi:        return "पार्किंग उपलब्ध"
        case .arabic:       return "مواقف متاحة"
        case .russian:      return "Парковка свободна"
        case .polish:       return "Miejsca parkingowe"
        }
    }

    var scaleOpenLabel: String {
        // Weigh station status — keep "Scale" in English (road term), translate descriptor
        switch self {
        case .english:      return "Scale OPEN"
        case .portuguese:   return "Balança ABERTA"
        case .spanish:      return "Báscula ABIERTA"
        case .spanishLatam: return "Báscula ABIERTA"
        case .french:       return "Balance OUVERTE"
        case .german:       return "Waage GEÖFFNET"
        case .hindi:        return "तराजू खुला"
        case .arabic:       return "الميزان مفتوح"
        case .russian:      return "Весовая ОТКРЫТА"
        case .polish:       return "Waga OTWARTA"
        }
    }

    var scaleClosedLabel: String {
        switch self {
        case .english:      return "Scale CLOSED"
        case .portuguese:   return "Balança FECHADA"
        case .spanish:      return "Báscula CERRADA"
        case .spanishLatam: return "Báscula CERRADA"
        case .french:       return "Balance FERMÉE"
        case .german:       return "Waage GESCHLOSSEN"
        case .hindi:        return "तराजू बंद"
        case .arabic:       return "الميزان مغلق"
        case .russian:      return "Весовая ЗАКРЫТА"
        case .polish:       return "Waga ZAMKNIĘTA"
        }
    }

    var scaleAheadLabel: String {
        // Distance warning before scale — "Weigh Station" stays in English
        switch self {
        case .english:      return "Weigh Station ahead"
        case .portuguese:   return "Balança à frente"
        case .spanish:      return "Báscula adelante"
        case .spanishLatam: return "Báscula adelante"
        case .french:       return "Balance devant"
        case .german:       return "Waage voraus"
        case .hindi:        return "आगे तराजू"
        case .arabic:       return "ميزان أمامك"
        case .russian:      return "Весовая впереди"
        case .polish:       return "Waga z przodu"
        }
    }

    var scaleMonitoringLabel: String {
        switch self {
        case .english:      return "Scale MONITORING"
        case .portuguese:   return "Balança MONITORANDO"
        case .spanish:      return "Báscula MONITOREANDO"
        case .spanishLatam: return "Báscula MONITOREANDO"
        case .french:       return "Balance SURVEILLÉE"
        case .german:       return "Waage ÜBERWACHT"
        case .hindi:        return "तराजू निगरानी"
        case .arabic:       return "الميزان تحت المراقبة"
        case .russian:      return "Весовая КОНТРОЛЬ"
        case .polish:       return "Waga MONITOROWANA"
        }
    }

    var scaleReportPromptLabel: String {
        switch self {
        case .english:      return "Report for other drivers"
        case .portuguese:   return "Reportar para outros motoristas"
        case .spanish:      return "Reportar para otros conductores"
        case .spanishLatam: return "Reportar para otros conductores"
        case .french:       return "Signaler aux autres chauffeurs"
        case .german:       return "Für andere Fahrer melden"
        case .hindi:        return "अन्य ड्राइवरों के लिए रिपोर्ट"
        case .arabic:       return "إبلاغ السائقين الآخرين"
        case .russian:      return "Сообщить другим водителям"
        case .polish:       return "Zgłoś innym kierowcom"
        }
    }

    var scaleReportThanksLabel: String {
        switch self {
        case .english:      return "Thanks — report sent"
        case .portuguese:   return "Obrigado — reporte enviado"
        case .spanish:      return "Gracias — reporte enviado"
        case .spanishLatam: return "Gracias — reporte enviado"
        case .french:       return "Merci — signalement envoyé"
        case .german:       return "Danke — Meldung gesendet"
        case .hindi:        return "धन्यवाद — रिपोर्ट भेजी गई"
        case .arabic:       return "شكراً — تم إرسال البلاغ"
        case .russian:      return "Спасибо — отчёт отправлен"
        case .polish:       return "Dzięki — zgłoszenie wysłane"
        }
    }

    var scaleMoreDetailsLabel: String {
        switch self {
        case .english:      return "More details (bypass / inspection)"
        case .portuguese:   return "Mais detalhes (bypass / inspeção)"
        case .spanish:      return "Más detalles (bypass / inspección)"
        case .spanishLatam: return "Más detalles (bypass / inspección)"
        case .french:       return "Plus de détails (contournement / inspection)"
        case .german:       return "Mehr Details (Bypass / Inspektion)"
        case .hindi:        return "अधिक विवरण (बाईपास / निरीक्षण)"
        case .arabic:       return "تفاصيل أكثر (تجاوز / تفتيش)"
        case .russian:      return "Подробнее (обход / инспекция)"
        case .polish:       return "Więcej szczegółów (objazd / inspekcja)"
        }
    }

    var scaleSelectStationLabel: String {
        switch self {
        case .english:      return "Select weigh station"
        case .portuguese:   return "Selecionar balança"
        case .spanish:      return "Seleccionar báscula"
        case .spanishLatam: return "Seleccionar báscula"
        case .french:       return "Choisir la station de pesée"
        case .german:       return "Waage auswählen"
        case .hindi:        return "वेट स्टेशन चुनें"
        case .arabic:       return "اختر محطة الوزن"
        case .russian:      return "Выберите весовую"
        case .polish:       return "Wybierz wagę"
        }
    }

    var scaleLoadingNearbyLabel: String {
        switch self {
        case .english:      return "Loading nearby scales…"
        case .portuguese:   return "Carregando balanças próximas…"
        case .spanish:      return "Cargando básculas cercanas…"
        case .spanishLatam: return "Cargando básculas cercanas…"
        case .french:       return "Chargement des stations à proximité…"
        case .german:       return "Waagen in der Nähe laden…"
        case .hindi:        return "पास की वेट स्टेशन लोड हो रही हैं…"
        case .arabic:       return "جاري تحميل محطات الوزن القريبة…"
        case .russian:      return "Загрузка весовых поблизости…"
        case .polish:       return "Ładowanie wag w pobliżu…"
        }
    }

    var scaleStatusUnconfirmedLabel: String {
        switch self {
        case .english:      return "Status not confirmed"
        case .portuguese:   return "Status não confirmado"
        case .spanish:      return "Estado no confirmado"
        case .spanishLatam: return "Estado no confirmado"
        case .french:       return "Statut non confirmé"
        case .german:       return "Status unbestätigt"
        case .hindi:        return "स्थिति अपुष्ट"
        case .arabic:       return "الحالة غير مؤكدة"
        case .russian:      return "Статус не подтверждён"
        case .polish:       return "Status niepotwierdzony"
        }
    }

    var scaleOfficialSourceLabel: String {
        switch self {
        case .english:      return "Official"
        case .portuguese:   return "Oficial"
        case .spanish:      return "Oficial"
        case .spanishLatam: return "Oficial"
        case .french:       return "Officiel"
        case .german:       return "Offiziell"
        case .hindi:        return "आधिकारिक"
        case .arabic:       return "رسمي"
        case .russian:      return "Официально"
        case .polish:       return "Oficjalne"
        }
    }

    var scaleCommunityAdvisoryLabel: String {
        switch self {
        case .english:      return "Driver report — unverified"
        case .portuguese:   return "Reporte de motorista — não verificado"
        case .spanish:      return "Reporte de conductor — no verificado"
        case .spanishLatam: return "Reporte de conductor — no verificado"
        case .french:       return "Signalement conducteur — non vérifié"
        case .german:       return "Fahrermeldung — unbestätigt"
        case .hindi:        return "ड्राइवर रिपोर्ट — अपुष्ट"
        case .arabic:       return "بلاغ سائق — غير مؤكد"
        case .russian:      return "Сообщение водителя — не проверено"
        case .polish:       return "Zgłoszenie kierowcy — niezweryfikowane"
        }
    }

    var scaleLocationOnlyHintLabel: String {
        switch self {
        case .english:      return "Official location — prepare to stop"
        case .portuguese:   return "Local oficial — prepare-se para parar"
        case .spanish:      return "Ubicación oficial — prepárate para parar"
        case .spanishLatam: return "Ubicación oficial — prepárate para parar"
        case .french:       return "Emplacement officiel — préparez-vous à vous arrêter"
        case .german:       return "Offizieller Standort — Stopp vorbereiten"
        case .hindi:        return "आधिकारिक स्थान — रुकने की तैयारी करें"
        case .arabic:       return "موقع رسمي — استعد للتوقف"
        case .russian:      return "Официальная точка — готовьтесь остановиться"
        case .polish:       return "Oficjalna lokalizacja — przygotuj się do zatrzymania"
        }
    }

    // MARK: - Navigation / Map labels
    var myLocationLabel: String {
        switch self {
        case .english:      return "My Location"
        case .portuguese:   return "Minha Localização"
        case .spanish:      return "Mi Ubicación"
        case .spanishLatam: return "Mi Ubicación"
        case .french:       return "Ma Position"
        case .german:       return "Mein Standort"
        case .hindi:        return "मेरा स्थान"
        case .arabic:       return "موقعي"
        case .russian:      return "Моё местоположение"
        case .polish:       return "Moja lokalizacja"
        }
    }

    var nearbyLabel: String {
        switch self {
        case .english:      return "Nearby"
        case .portuguese:   return "Perto"
        case .spanish:      return "Cercano"
        case .spanishLatam: return "Cercano"
        case .french:       return "À proximité"
        case .german:       return "In der Nähe"
        case .hindi:        return "नजदीक"
        case .arabic:       return "قريب"
        case .russian:      return "Рядом"
        case .polish:       return "W pobliżu"
        }
    }

    // Wellness strings
    var wellnessPriority: String {
        switch self {
        case .english:      return "Your wellness is our priority"
        case .portuguese:   return "Seu bem-estar é prioridade"
        case .spanish:      return "Tu bienestar es prioridad"
        case .spanishLatam: return "Tu bienestar es prioridad"
        case .french:       return "Votre bien-être est prioritaire"
        case .german:       return "Ihr Wohlbefinden hat Priorität"
        case .hindi:        return "आपकी सेहत हमारी प्राथमिकता है"
        case .arabic:       return "صحتك أولويتنا"
        case .russian:      return "Ваше здоровье — наш приоритет"
        case .polish:       return "Twoje zdrowie jest naszym priorytetem"
        }
    }

    var howAreYouFeeling: String {
        switch self {
        case .english:      return "How are you feeling?"
        case .portuguese:   return "Como você está se sentindo?"
        case .spanish:      return "¿Cómo te sientes?"
        case .spanishLatam: return "¿Cómo te sentís?"
        case .french:       return "Comment vous sentez-vous?"
        case .german:       return "Wie fühlen Sie sich?"
        case .hindi:        return "आप कैसा महसूस कर रहे हैं?"
        case .arabic:       return "كيف تشعر؟"
        case .russian:      return "Как вы себя чувствуете?"
        case .polish:       return "Jak się czujesz?"
        }
    }

    // Wellness check-in strings (launch modal)
    var goodMorningDriver: String {
        switch self {
        case .english:      return "Good morning, Driver!"
        case .portuguese:   return "Bom dia, Motorista!"
        case .spanish:      return "¡Buenos días, Conductor!"
        case .spanishLatam: return "¡Buen día, Conductor!"
        case .french:       return "Bonjour, Conducteur!"
        case .german:       return "Guten Morgen, Fahrer!"
        case .hindi:        return "सुप्रभात, ड्राइवर!"
        case .arabic:       return "صباح الخير، سائق!"
        case .russian:      return "Доброе утро, Водитель!"
        case .polish:       return "Dzień dobry, Kierowco!"
        }
    }

    var dailyCheckInTitle: String {
        switch self {
        case .english:      return "Daily Safety Check-in"
        case .portuguese:   return "Check-in de Segurança Diário"
        case .spanish:      return "Control Diario de Seguridad"
        case .spanishLatam: return "Chequeo Diario de Seguridad"
        case .french:       return "Bilan Sécurité Quotidien"
        case .german:       return "Täglicher Sicherheits-Check"
        case .hindi:        return "दैनिक सुरक्षा जाँच"
        case .arabic:       return "تسجيل الحضور اليومي للسلامة"
        case .russian:      return "Ежедневная проверка безопасности"
        case .polish:       return "Dzienny Przegląd Bezpieczeństwa"
        }
    }

    var readyToDriveLabel: String {
        switch self {
        case .english:      return "Ready to Drive?"
        case .portuguese:   return "Pronto para Dirigir?"
        case .spanish:      return "¿Listo para Conducir?"
        case .spanishLatam: return "¿Listo para manejar?"
        case .french:       return "Prêt à Conduire?"
        case .german:       return "Bereit zum Fahren?"
        case .hindi:        return "ड्राइव करने के लिए तैयार?"
        case .arabic:       return "مستعد للقيادة؟"
        case .russian:      return "Готов ехать?"
        case .polish:       return "Gotowy do jazdy?"
        }
    }

    var startDrivingLabel: String {
        switch self {
        case .english:      return "Start Driving"
        case .portuguese:   return "Começar a Dirigir"
        case .spanish:      return "Empezar a Conducir"
        case .spanishLatam: return "Empezar a manejar"
        case .french:       return "Commencer à conduire"
        case .german:       return "Fahren beginnen"
        case .hindi:        return "ड्राइव शुरू करें"
        case .arabic:       return "ابدأ القيادة"
        case .russian:      return "Начать движение"
        case .polish:       return "Zacznij jazdę"
        }
    }

    // HOS strings
    var hosTitle: String {
        switch self {
        case .english:      return "HOS Rules"
        case .portuguese:   return "Regras de Jornada"
        case .spanish:      return "Reglas HOS"
        case .spanishLatam: return "Reglas HOS"
        case .french:       return "Règles du Temps de Conduite"
        case .german:       return "Lenkzeitregeln"
        case .hindi:        return "HOS नियम"
        case .arabic:       return "قواعد ساعات الخدمة"
        case .russian:      return "Правила рабочего времени"
        case .polish:       return "Zasady czasu pracy"
        }
    }

    var maxDrivingLabel: String {
        switch self {
        case .english:      return "Max driving/day"
        case .portuguese:   return "Máx. direção/dia"
        case .spanish:      return "Máx. conducción/día"
        case .spanishLatam: return "Máx. manejo/día"
        case .french:       return "Conduite max/jour"
        case .german:       return "Max Fahrt/Tag"
        case .hindi:        return "अधिकतम ड्राइविंग/दिन"
        case .arabic:       return "أقصى قيادة/يوم"
        case .russian:      return "Макс. вождение/день"
        case .polish:       return "Maks. jazda/dzień"
        }
    }

    var serviceWindowLabel: String {
        switch self {
        case .english:      return "Service window"
        case .portuguese:   return "Janela de serviço"
        case .spanish:      return "Ventana de servicio"
        case .spanishLatam: return "Ventana de servicio"
        case .french:       return "Fenêtre de service"
        case .german:       return "Dienstfenster"
        case .hindi:        return "सेवा विंडो"
        case .arabic:       return "نافذة الخدمة"
        case .russian:      return "Рабочее окно"
        case .polish:       return "Okno czasu pracy"
        }
    }

    var mandatoryBreakLabel: String {
        switch self {
        case .english:      return "Mandatory break"
        case .portuguese:   return "Pausa obrigatória"
        case .spanish:      return "Pausa obligatoria"
        case .spanishLatam: return "Pausa obligatoria"
        case .french:       return "Pause obligatoire"
        case .german:       return "Pflichtpause"
        case .hindi:        return "अनिवार्य विराम"
        case .arabic:       return "استراحة إلزامية"
        case .russian:      return "Обязательный перерыв"
        case .polish:       return "Obowiązkowa przerwa"
        }
    }

    var restBetweenShiftsLabel: String {
        switch self {
        case .english:      return "Rest between shifts"
        case .portuguese:   return "Descanso entre turnos"
        case .spanish:      return "Descanso entre turnos"
        case .spanishLatam: return "Descanso entre turnos"
        case .french:       return "Repos entre quarts"
        case .german:       return "Ruhe zwischen Schichten"
        case .hindi:        return "शिफ्ट के बीच आराम"
        case .arabic:       return "راحة بين المناوبات"
        case .russian:      return "Отдых между сменами"
        case .polish:       return "Odpoczynek między zmianami"
        }
    }

    var weeklyLimitLabel: String {
        switch self {
        case .english:      return "Weekly limit"
        case .portuguese:   return "Limite semanal"
        case .spanish:      return "Límite semanal"
        case .spanishLatam: return "Límite semanal"
        case .french:       return "Limite hebdomadaire"
        case .german:       return "Wochenlimit"
        case .hindi:        return "साप्ताहिक सीमा"
        case .arabic:       return "الحد الأسبوعي"
        case .russian:      return "Недельный лимит"
        case .polish:       return "Limit tygodniowy"
        }
    }

    var weightLimitLabel: String {
        switch self {
        case .english:      return "Max weight"
        case .portuguese:   return "Peso máximo"
        case .spanish:      return "Peso máximo"
        case .spanishLatam: return "Peso máximo"
        case .french:       return "Poids maximum"
        case .german:       return "Maximalgewicht"
        case .hindi:        return "अधिकतम वजन"
        case .arabic:       return "الوزن الأقصى"
        case .russian:      return "Макс. вес"
        case .polish:       return "Maks. waga"
        }
    }

    // Map strings
    var whereToLabel: String {
        switch self {
        case .english:      return "Where to?"
        case .portuguese:   return "Para onde?"
        case .spanish:      return "¿A dónde?"
        case .spanishLatam: return "¿A dónde?"
        case .french:       return "Où aller?"
        case .german:       return "Wohin?"
        case .hindi:        return "कहाँ जाना है?"
        case .arabic:       return "إلى أين؟"
        case .russian:      return "Куда едем?"
        case .polish:       return "Dokąd?"
        }
    }

    var currentLocationLabel: String {
        switch self {
        case .english:      return "Current Location"
        case .portuguese:   return "Localização Atual"
        case .spanish:      return "Ubicación Actual"
        case .spanishLatam: return "Ubicación Actual"
        case .french:       return "Position Actuelle"
        case .german:       return "Aktueller Standort"
        case .hindi:        return "वर्तमान स्थान"
        case .arabic:       return "الموقع الحالي"
        case .russian:      return "Текущее местоположение"
        case .polish:       return "Aktualna lokalizacja"
        }
    }

    var gotALoadLabel: String {
        switch self {
        case .english:      return "Got a Load?"
        case .portuguese:   return "Tem uma Carga?"
        case .spanish:      return "¿Tienes Carga?"
        case .spanishLatam: return "¿Tienes Carga?"
        case .french:       return "Vous avez un Chargement?"
        case .german:       return "Ladung bekommen?"
        case .hindi:        return "माल मिला?"
        case .arabic:       return "هل لديك شحنة؟"
        case .russian:      return "Есть груз?"
        case .polish:       return "Masz ładunek?"
        }
    }

    var startNavigationLabel: String {
        switch self {
        case .english:      return "Start Navigation"
        case .portuguese:   return "Iniciar Navegação"
        case .spanish:      return "Iniciar Navegación"
        case .spanishLatam: return "Iniciar Navegación"
        case .french:       return "Démarrer la Navigation"
        case .german:       return "Navigation starten"
        case .hindi:        return "नेविगेशन शुरू करें"
        case .arabic:       return "بدء الملاحة"
        case .russian:      return "Начать навигацию"
        case .polish:       return "Rozpocznij nawigację"
        }
    }

    var activeTripLabel: String {
        switch self {
        case .english:      return "Active Trip"
        case .portuguese:   return "Viagem Ativa"
        case .spanish:      return "Viaje Activo"
        case .spanishLatam: return "Viaje Activo"
        case .french:       return "Trajet en cours"
        case .german:       return "Aktive Fahrt"
        case .hindi:        return "सक्रिय यात्रा"
        case .arabic:       return "الرحلة النشطة"
        case .russian:      return "Активная поездка"
        case .polish:       return "Aktywna podróż"
        }
    }

    // Document strings
    var documentsLabel: String {
        switch self {
        case .english:      return "Documents"
        case .portuguese:   return "Documentos"
        case .spanish:      return "Documentos"
        case .spanishLatam: return "Documentos"
        case .french:       return "Documents"
        case .german:       return "Dokumente"
        case .hindi:        return "दस्तावेज़"
        case .arabic:       return "الوثائق"
        case .russian:      return "Документы"
        case .polish:       return "Dokumenty"
        }
    }

    var expiresLabel: String {
        switch self {
        case .english:      return "Expires"
        case .portuguese:   return "Vence"
        case .spanish:      return "Vence"
        case .spanishLatam: return "Vence"
        case .french:       return "Expire"
        case .german:       return "Läuft ab"
        case .hindi:        return "समाप्त होता है"
        case .arabic:       return "ينتهي"
        case .russian:      return "Истекает"
        case .polish:       return "Wygasa"
        }
    }

    // Fatigue warning
    // MARK: - RoadTalk section labels
    var roadTalkNewsLabel: String {
        switch self {
        case .english:      return "News"
        case .portuguese:   return "Notícias"
        case .spanish:      return "Noticias"
        case .spanishLatam: return "Noticias"
        case .french:       return "Actualités"
        case .german:       return "Nachrichten"
        case .hindi:        return "समाचार"
        case .arabic:       return "أخبار"
        case .russian:      return "Новости"
        case .polish:       return "Wiadomości"
        }
    }

    var roadTalkReportLabel: String {
        switch self {
        case .english:      return "Report"
        case .portuguese:   return "Reportar"
        case .spanish:      return "Reportar"
        case .spanishLatam: return "Reportar"
        case .french:       return "Signaler"
        case .german:       return "Melden"
        case .hindi:        return "रिपोर्ट"
        case .arabic:       return "تقرير"
        case .russian:      return "Сообщить"
        case .polish:       return "Zgłoś"
        }
    }

    var roadTalkCommunityLabel: String {
        switch self {
        case .english:      return "Community"
        case .portuguese:   return "Comunidade"
        case .spanish:      return "Comunidad"
        case .spanishLatam: return "Comunidad"
        case .french:       return "Communauté"
        case .german:       return "Gemeinschaft"
        case .hindi:        return "समुदाय"
        case .arabic:       return "مجتمع"
        case .russian:      return "Сообщество"
        case .polish:       return "Społeczność"
        }
    }

    var roadTalkAILabel: String {
        switch self {
        case .english:      return "Easy AI"
        case .portuguese:   return "Easy IA"
        case .spanish:      return "Easy IA"
        case .spanishLatam: return "Easy IA"
        case .french:       return "Easy IA"
        case .german:       return "Easy KI"
        case .hindi:        return "Easy AI"
        case .arabic:       return "Easy AI"
        case .russian:      return "Easy ИИ"
        case .polish:       return "Easy AI"
        }
    }

    var roadTalkSubtitle: String {
        switch self {
        case .english:      return "News · Reports · Community · AI"
        case .portuguese:   return "Notícias · Relatórios · Comunidade · IA"
        case .spanish:      return "Noticias · Reportes · Comunidad · IA"
        case .spanishLatam: return "Noticias · Reportes · Comunidad · IA"
        case .french:       return "Actualités · Rapports · Communauté · IA"
        case .german:       return "Nachrichten · Berichte · Gemeinschaft · KI"
        case .hindi:        return "समाचार · रिपोर्ट · समुदाय · AI"
        case .arabic:       return "أخبار · تقارير · مجتمع · AI"
        case .russian:      return "Новости · Отчёты · Сообщество · ИИ"
        case .polish:       return "Wiadomości · Raporty · Społeczność · AI"
        }
    }

    // MARK: - Checkup section labels
    var checkupTitle: String {
        switch self {
        case .english:      return "My Check-up"
        case .portuguese:   return "Meu Check-up"
        case .spanish:      return "Mi Chequeo"
        case .spanishLatam: return "Mi Chequeo"
        case .french:       return "Mon Bilan"
        case .german:       return "Mein Check-up"
        case .hindi:        return "मेरी जाँच"
        case .arabic:       return "فحصي"
        case .russian:      return "Моё Здоровье"
        case .polish:       return "Moje Zdrowie"
        }
    }

    var todayLabel: String {
        switch self {
        case .english:      return "TODAY"
        case .portuguese:   return "HOJE"
        case .spanish:      return "HOY"
        case .spanishLatam: return "HOY"
        case .french:       return "AUJOURD'HUI"
        case .german:       return "HEUTE"
        case .hindi:        return "आज"
        case .arabic:       return "اليوم"
        case .russian:      return "СЕГОДНЯ"
        case .polish:       return "DZISIAJ"
        }
    }

    var savedLabel: String {
        switch self {
        case .english:      return "Saved"
        case .portuguese:   return "Salvo"
        case .spanish:      return "Guardado"
        case .spanishLatam: return "Guardado"
        case .french:       return "Enregistré"
        case .german:       return "Gespeichert"
        case .hindi:        return "सहेजा"
        case .arabic:       return "محفوظ"
        case .russian:      return "Сохранено"
        case .polish:       return "Zapisano"
        }
    }

    var dayStatusLabel: String {
        switch self {
        case .english:      return "DAY STATUS"
        case .portuguese:   return "STATUS DO DIA"
        case .spanish:      return "ESTADO DEL DÍA"
        case .spanishLatam: return "ESTADO DEL DÍA"
        case .french:       return "STATUT DU JOUR"
        case .german:       return "TAGESSTATUS"
        case .hindi:        return "दिन की स्थिति"
        case .arabic:       return "حالة اليوم"
        case .russian:      return "СТАТУС ДНЯ"
        case .polish:       return "STATUS DNIA"
        }
    }

    var tapStarMoodLabel: String {
        switch self {
        case .english:      return "Tap a star to log your mood"
        case .portuguese:   return "Toque em uma estrela para registrar seu humor"
        case .spanish:      return "Toca una estrella para registrar tu estado de ánimo"
        case .spanishLatam: return "Tocá una estrella para registrar tu estado de ánimo"
        case .french:       return "Appuyez sur une étoile pour noter votre humeur"
        case .german:       return "Tippen Sie auf einen Stern um Ihre Stimmung zu speichern"
        case .hindi:        return "मूड दर्ज करने के लिए एक स्टार टैप करें"
        case .arabic:       return "اضغط على نجمة لتسجيل مزاجك"
        case .russian:      return "Нажмите на звезду чтобы записать настроение"
        case .polish:       return "Dotknij gwiazdkę aby zapisać nastrój"
        }
    }

    // MARK: - Cabin section labels
    var cabinTitle: String {
        switch self {
        case .english:      return "My Cabin"
        case .portuguese:   return "Minha Cabine"
        case .spanish:      return "Mi Cabina"
        case .spanishLatam: return "Mi Cabina"
        case .french:       return "Ma Cabine"
        case .german:       return "Meine Kabine"
        case .hindi:        return "मेरी कैबिन"
        case .arabic:       return "كابينتي"
        case .russian:      return "Моя Кабина"
        case .polish:       return "Moja Kabina"
        }
    }

    var cabinSubtitle: String {
        switch self {
        case .english:      return "Digital Document Vault"
        case .portuguese:   return "Cofre de Documentos Digital"
        case .spanish:      return "Bóveda de Documentos Digital"
        case .spanishLatam: return "Bóveda de Documentos Digital"
        case .french:       return "Coffre-fort de Documents"
        case .german:       return "Digitaler Dokumententresor"
        case .hindi:        return "डिजिटल दस्तावेज़ तिजोरी"
        case .arabic:       return "خزنة وثائق رقمية"
        case .russian:      return "Цифровое Хранилище Документов"
        case .polish:       return "Cyfrowy Sejf Dokumentów"
        }
    }

    var addDocumentLabel: String {
        switch self {
        case .english:      return "Add Document"
        case .portuguese:   return "Adicionar Documento"
        case .spanish:      return "Agregar Documento"
        case .spanishLatam: return "Agregar Documento"
        case .french:       return "Ajouter un Document"
        case .german:       return "Dokument hinzufügen"
        case .hindi:        return "दस्तावेज़ जोड़ें"
        case .arabic:       return "إضافة وثيقة"
        case .russian:      return "Добавить документ"
        case .polish:       return "Dodaj dokument"
        }
    }

    var fatigueWarning: String {
        switch self {
        case .english:      return "WARNING: Possible fatigue. Do not drive if sleepy."
        case .portuguese:   return "ATENÇÃO: Possível fadiga. Não dirija com sono."
        case .spanish:      return "ADVERTENCIA: Posible fatiga. No conduzca si tiene sueño."
        case .spanishLatam: return "ADVERTENCIA: Posible fatiga. No maneje si tiene sueño."
        case .french:       return "AVERTISSEMENT: Fatigue possible. Ne pas conduire si somnolent."
        case .german:       return "WARNUNG: Mögliche Müdigkeit. Nicht fahren wenn schläfrig."
        case .hindi:        return "चेतावनी: थकान संभव। नींद आने पर गाड़ी न चलाएं।"
        case .arabic:       return "تحذير: تعب محتمل. لا تقود إذا كنت نعساناً."
        case .russian:      return "ВНИМАНИЕ: Возможная усталость. Не садитесь за руль при сонливости."
        case .polish:       return "OSTRZEŻENIE: Możliwe zmęczenie. Nie prowadź, jeśli jesteś śpiący."
        }
    }

    // MARK: - Wellness status messages
    var statusGreat: String {
        switch self {
        case .english:      return "You're in great shape today! Drive safely."
        case .portuguese:   return "Você está ótimo hoje! Dirija com segurança."
        case .spanish:      return "¡Estás en gran forma hoy! Conduce con cuidado."
        case .spanishLatam: return "¡Estás en gran forma hoy! Manejá con cuidado."
        case .french:       return "Vous êtes en grande forme aujourd'hui! Conduisez prudemment."
        case .german:       return "Sie sind heute in guter Verfassung! Fahren Sie sicher."
        case .hindi:        return "आज आप बेहतरीन स्थिति में हैं! सुरक्षित गाड़ी चलाएं।"
        case .arabic:       return "أنت في حالة رائعة اليوم! قد بأمان."
        case .russian:      return "Вы в отличной форме сегодня! Езжайте осторожно."
        case .polish:       return "Jesteś dziś w świetnej formie! Jedź bezpiecznie."
        }
    }

    var statusGood: String {
        switch self {
        case .english:      return "You're doing well. Stay alert and rest when needed."
        case .portuguese:   return "Você está bem. Fique alerta e descanse quando necessário."
        case .spanish:      return "Estás bien. Mantente alerta y descansa cuando sea necesario."
        case .spanishLatam: return "Estás bien. Quedate alerta y descansá cuando sea necesario."
        case .french:       return "Vous allez bien. Restez vigilant et reposez-vous si nécessaire."
        case .german:       return "Es geht Ihnen gut. Bleiben Sie wachsam und ruhen Sie sich aus."
        case .hindi:        return "आप ठीक हैं। सतर्क रहें और जरूरत पड़ने पर आराम करें।"
        case .arabic:       return "حالك جيدة. ابق يقظاً واسترح عند الحاجة."
        case .russian:      return "У вас всё хорошо. Будьте внимательны и отдыхайте при необходимости."
        case .polish:       return "Jesteś w dobrej formie. Bądź czujny i odpoczywaj gdy potrzeba."
        }
    }

    var statusFatigue: String {
        switch self {
        case .english:      return "Signs of fatigue. Consider a break or 20-min nap."
        case .portuguese:   return "Sinais de fadiga. Considere uma pausa ou cochilo de 20 min."
        case .spanish:      return "Señales de fatiga. Considera un descanso o siesta de 20 min."
        case .spanishLatam: return "Señales de fatiga. Considerá un descanso o siesta de 20 min."
        case .french:       return "Signes de fatigue. Envisagez une pause ou une sieste de 20 min."
        case .german:       return "Zeichen von Müdigkeit. Machen Sie eine Pause oder ein 20-Min-Nickerchen."
        case .hindi:        return "थकान के संकेत। 20 मिनट की झपकी लें।"
        case .arabic:       return "علامات تعب. فكر في استراحة أو قيلولة 20 دقيقة."
        case .russian:      return "Признаки усталости. Сделайте перерыв или вздремните 20 минут."
        case .polish:       return "Oznaki zmęczenia. Rozważ przerwę lub 20-minutową drzemkę."
        }
    }

    // MARK: - Vital labels
    var sleepLabel: String {
        switch self {
        case .english:      return "Sleep"
        case .portuguese:   return "Sono"
        case .spanish:      return "Sueño"
        case .spanishLatam: return "Sueño"
        case .french:       return "Sommeil"
        case .german:       return "Schlaf"
        case .hindi:        return "नींद"
        case .arabic:       return "نوم"
        case .russian:      return "Сон"
        case .polish:       return "Sen"
        }
    }

    var exerciseLabel: String {
        switch self {
        case .english:      return "Exercise"
        case .portuguese:   return "Exercício"
        case .spanish:      return "Ejercicio"
        case .spanishLatam: return "Ejercicio"
        case .french:       return "Exercice"
        case .german:       return "Sport"
        case .hindi:        return "व्यायाम"
        case .arabic:       return "تمرين"
        case .russian:      return "Упражнения"
        case .polish:       return "Ćwiczenia"
        }
    }

    var waterLabel: String {
        switch self {
        case .english:      return "Water"
        case .portuguese:   return "Água"
        case .spanish:      return "Agua"
        case .spanishLatam: return "Agua"
        case .french:       return "Eau"
        case .german:       return "Wasser"
        case .hindi:        return "पानी"
        case .arabic:       return "ماء"
        case .russian:      return "Вода"
        case .polish:       return "Woda"
        }
    }

    var moodLabel: String {
        switch self {
        case .english:      return "Mood"
        case .portuguese:   return "Humor"
        case .spanish:      return "Humor"
        case .spanishLatam: return "Ánimo"
        case .french:       return "Humeur"
        case .german:       return "Stimmung"
        case .hindi:        return "मनोदशा"
        case .arabic:       return "مزاج"
        case .russian:      return "Настрой"
        case .polish:       return "Nastrój"
        }
    }

    var medicationsLabel: String {
        switch self {
        case .english:      return "Medications"
        case .portuguese:   return "Medicamentos"
        case .spanish:      return "Medicamentos"
        case .spanishLatam: return "Medicamentos"
        case .french:       return "Médicaments"
        case .german:       return "Medikamente"
        case .hindi:        return "दवाइयाँ"
        case .arabic:       return "أدوية"
        case .russian:      return "Лекарства"
        case .polish:       return "Leki"
        }
    }

    var pendingLabel: String {
        switch self {
        case .english:      return "pending"
        case .portuguese:   return "pendente"
        case .spanish:      return "pendiente"
        case .spanishLatam: return "pendiente"
        case .french:       return "en attente"
        case .german:       return "ausstehend"
        case .hindi:        return "लंबित"
        case .arabic:       return "معلق"
        case .russian:      return "ожидает"
        case .polish:       return "oczekujący"
        }
    }

    var addMedicationLabel: String {
        switch self {
        case .english:      return "Add medication reminder"
        case .portuguese:   return "Adicionar lembrete de medicamento"
        case .spanish:      return "Agregar recordatorio de medicamento"
        case .spanishLatam: return "Agregar recordatorio de medicamento"
        case .french:       return "Ajouter un rappel de médicament"
        case .german:       return "Medikamentenerinnerung hinzufügen"
        case .hindi:        return "दवा रिमाइंडर जोड़ें"
        case .arabic:       return "إضافة تذكير دواء"
        case .russian:      return "Добавить напоминание о лекарстве"
        case .polish:       return "Dodaj przypomnienie o leku"
        }
    }

    var medicationTimeLabel: String {
        switch self {
        case .english:      return "Time for your medication!"
        case .portuguese:   return "Hora do seu medicamento!"
        case .spanish:      return "¡Hora de tu medicamento!"
        case .spanishLatam: return "¡Hora de tu medicamento!"
        case .french:       return "Il est l'heure de prendre votre médicament!"
        case .german:       return "Zeit für Ihre Medikamente!"
        case .hindi:        return "आपकी दवा का समय हो गया!"
        case .arabic:       return "حان وقت دوائك!"
        case .russian:      return "Время принять лекарство!"
        case .polish:       return "Czas na lek!"
        }
    }

    var remindLaterLabel: String {
        switch self {
        case .english:      return "Remind me later"
        case .portuguese:   return "Lembrar daqui a pouco"
        case .spanish:      return "Recordarme más tarde"
        case .spanishLatam: return "Recordarme más tarde"
        case .french:       return "Me rappeler plus tard"
        case .german:       return "Später erinnern"
        case .hindi:        return "बाद में याद दिलाएं"
        case .arabic:       return "ذكرني لاحقاً"
        case .russian:      return "Напомнить позже"
        case .polish:       return "Przypomnij później"
        }
    }

    var todayActivityLabel: String {
        switch self {
        case .english:      return "TODAY'S ACTIVITY"
        case .portuguese:   return "ATIVIDADE DE HOJE"
        case .spanish:      return "ACTIVIDAD DE HOY"
        case .spanishLatam: return "ACTIVIDAD DE HOY"
        case .french:       return "ACTIVITÉ DU JOUR"
        case .german:       return "HEUTIGE AKTIVITÄT"
        case .hindi:        return "आज की गतिविधि"
        case .arabic:       return "نشاط اليوم"
        case .russian:      return "АКТИВНОСТЬ СЕГОДНЯ"
        case .polish:       return "AKTYWNOŚĆ DZISIAJ"
        }
    }

    var driverTipsLabel: String {
        switch self {
        case .english:      return "DRIVER TIPS"
        case .portuguese:   return "DICAS PARA MOTORISTAS"
        case .spanish:      return "CONSEJOS PARA CONDUCTORES"
        case .spanishLatam: return "CONSEJOS PARA CONDUCTORES"
        case .french:       return "CONSEILS CONDUCTEUR"
        case .german:       return "FAHRER-TIPPS"
        case .hindi:        return "ड्राइवर टिप्स"
        case .arabic:       return "نصائح للسائق"
        case .russian:      return "СОВЕТЫ ВОДИТЕЛЮ"
        case .polish:       return "WSKAZÓWKI DLA KIEROWCY"
        }
    }

    // MARK: - Cabin / Document labels
    var filterAll: String {
        switch self {
        case .english:      return "All"
        case .portuguese:   return "Todos"
        case .spanish:      return "Todos"
        case .spanishLatam: return "Todos"
        case .french:       return "Tous"
        case .german:       return "Alle"
        case .hindi:        return "सभी"
        case .arabic:       return "الكل"
        case .russian:      return "Все"
        case .polish:       return "Wszystkie"
        }
    }

    var filterExpiring: String {
        switch self {
        case .english:      return "Expiring"
        case .portuguese:   return "Vencendo"
        case .spanish:      return "Por vencer"
        case .spanishLatam: return "Por vencer"
        case .french:       return "Expire bientôt"
        case .german:       return "Läuft bald ab"
        case .hindi:        return "समाप्त होने वाले"
        case .arabic:       return "تنتهي قريباً"
        case .russian:      return "Истекают"
        case .polish:       return "Wygasające"
        }
    }

    var filterExpired: String {
        switch self {
        case .english:      return "Expired"
        case .portuguese:   return "Vencido"
        case .spanish:      return "Vencido"
        case .spanishLatam: return "Vencido"
        case .french:       return "Expiré"
        case .german:       return "Abgelaufen"
        case .hindi:        return "समाप्त"
        case .arabic:       return "منتهي"
        case .russian:      return "Просрочен"
        case .polish:       return "Wygasłe"
        }
    }

    var filterOk: String {
        switch self {
        case .english:      return "OK"
        case .portuguese:   return "OK"
        case .spanish:      return "OK"
        case .spanishLatam: return "OK"
        case .french:       return "OK"
        case .german:       return "OK"
        case .hindi:        return "ठीक"
        case .arabic:       return "بخير"
        case .russian:      return "ОК"
        case .polish:       return "OK"
        }
    }

    var actionRequiredLabel: String {
        switch self {
        case .english:      return "ACTION REQUIRED"
        case .portuguese:   return "AÇÃO NECESSÁRIA"
        case .spanish:      return "ACCIÓN REQUERIDA"
        case .spanishLatam: return "ACCIÓN REQUERIDA"
        case .french:       return "ACTION REQUISE"
        case .german:       return "AKTION ERFORDERLICH"
        case .hindi:        return "कार्रवाई आवश्यक"
        case .arabic:       return "إجراء مطلوب"
        case .russian:      return "ТРЕБУЕТСЯ ДЕЙСТВИЕ"
        case .polish:       return "WYMAGANE DZIAŁANIE"
        }
    }

    var vaultEmptyTitle: String {
        switch self {
        case .english:      return "Your vault is empty"
        case .portuguese:   return "Seu cofre está vazio"
        case .spanish:      return "Tu bóveda está vacía"
        case .spanishLatam: return "Tu bóveda está vacía"
        case .french:       return "Votre coffre est vide"
        case .german:       return "Ihr Tresor ist leer"
        case .hindi:        return "आपकी तिजोरी खाली है"
        case .arabic:       return "خزنتك فارغة"
        case .russian:      return "Ваше хранилище пустое"
        case .polish:       return "Twój sejf jest pusty"
        }
    }

    var quickScanLabel: String {
        switch self {
        case .english:      return "QUICK SCAN"
        case .portuguese:   return "DIGITALIZAR RÁPIDO"
        case .spanish:      return "ESCANEO RÁPIDO"
        case .spanishLatam: return "ESCANEO RÁPIDO"
        case .french:       return "SCAN RAPIDE"
        case .german:       return "SCHNELLSCAN"
        case .hindi:        return "त्वरित स्कैन"
        case .arabic:       return "مسح سريع"
        case .russian:      return "БЫСТРОЕ СКАНИРОВАНИЕ"
        case .polish:       return "SZYBKIE SKANOWANIE"
        }
    }

    var driverToolsLabel: String {
        switch self {
        case .english:      return "DRIVER TOOLS"
        case .portuguese:   return "FERRAMENTAS DO MOTORISTA"
        case .spanish:      return "HERRAMIENTAS DEL CONDUCTOR"
        case .spanishLatam: return "HERRAMIENTAS DEL CONDUCTOR"
        case .french:       return "OUTILS CONDUCTEUR"
        case .german:       return "FAHRERWERKZEUGE"
        case .hindi:        return "ड्राइवर टूल्स"
        case .arabic:       return "أدوات السائق"
        case .russian:      return "ИНСТРУМЕНТЫ ВОДИТЕЛЯ"
        case .polish:       return "NARZĘDZIA KIEROWCY"
        }
    }

    var truckSignsLabel: String {
        switch self {
        case .english:      return "Truck Signs Guide"
        case .portuguese:   return "Guia de Placas para Caminhões"
        case .spanish:      return "Guía de Señales para Camiones"
        case .spanishLatam: return "Guía de Señales para Camiones"
        case .french:       return "Guide des Panneaux Poids Lourds"
        case .german:       return "LKW-Schilderführer"
        case .hindi:        return "ट्रक संकेत गाइड"
        case .arabic:       return "دليل لافتات الشاحنات"
        case .russian:      return "Руководство по знакам для грузовиков"
        case .polish:       return "Przewodnik po znakach dla ciężarówek"
        }
    }

    // MARK: - Driver Profile section labels
    var profileTitle: String {
        switch self {
        case .english:      return "My Profile"
        case .portuguese:   return "Meu Perfil"
        case .spanish:      return "Mi Perfil"
        case .spanishLatam: return "Mi Perfil"
        case .french:       return "Mon Profil"
        case .german:       return "Mein Profil"
        case .hindi:        return "मेरी प्रोफ़ाइल"
        case .arabic:       return "ملفي"
        case .russian:      return "Мой Профиль"
        case .polish:       return "Mój Profil"
        }
    }

    var wellnessSectionLabel: String {
        switch self {
        case .english:      return "WELLNESS"
        case .portuguese:   return "BEM-ESTAR"
        case .spanish:      return "BIENESTAR"
        case .spanishLatam: return "BIENESTAR"
        case .french:       return "BIEN-ÊTRE"
        case .german:       return "WOHLBEFINDEN"
        case .hindi:        return "स्वास्थ्य"
        case .arabic:       return "الصحة"
        case .russian:      return "ЗДОРОВЬЕ"
        case .polish:       return "ZDROWIE"
        }
    }

    var foodSectionLabel: String {
        switch self {
        case .english:      return "FOOD & NUTRITION"
        case .portuguese:   return "ALIMENTAÇÃO"
        case .spanish:      return "ALIMENTACIÓN"
        case .spanishLatam: return "ALIMENTACIÓN"
        case .french:       return "ALIMENTATION"
        case .german:       return "ERNÄHRUNG"
        case .hindi:        return "भोजन और पोषण"
        case .arabic:       return "الغذاء والتغذية"
        case .russian:      return "ПИТАНИЕ"
        case .polish:       return "ŻYWIENIE"
        }
    }

    var historySectionLabel: String {
        switch self {
        case .english:      return "HISTORY & RATINGS"
        case .portuguese:   return "HISTÓRICO E AVALIAÇÕES"
        case .spanish:      return "HISTORIAL Y CALIFICACIONES"
        case .spanishLatam: return "HISTORIAL Y CALIFICACIONES"
        case .french:       return "HISTORIQUE ET NOTES"
        case .german:       return "VERLAUF UND BEWERTUNGEN"
        case .hindi:        return "इतिहास और रेटिंग"
        case .arabic:       return "السجل والتقييمات"
        case .russian:      return "ИСТОРИЯ И ОЦЕНКИ"
        case .polish:       return "HISTORIA I OCENY"
        }
    }

    var complianceSectionLabel: String {
        switch self {
        case .english:      return "COMPLIANCE & DOCUMENTS"
        case .portuguese:   return "CONFORMIDADE E DOCUMENTOS"
        case .spanish:      return "CUMPLIMIENTO Y DOCUMENTOS"
        case .spanishLatam: return "CUMPLIMIENTO Y DOCUMENTOS"
        case .french:       return "CONFORMITÉ ET DOCUMENTS"
        case .german:       return "COMPLIANCE UND DOKUMENTE"
        case .hindi:        return "अनुपालन और दस्तावेज़"
        case .arabic:       return "الامتثال والوثائق"
        case .russian:      return "СООТВЕТСТВИЕ И ДОКУМЕНТЫ"
        case .polish:       return "ZGODNOŚĆ I DOKUMENTY"
        }
    }

    var settingsSectionLabel: String {
        switch self {
        case .english:      return "SETTINGS"
        case .portuguese:   return "CONFIGURAÇÕES"
        case .spanish:      return "CONFIGURACIÓN"
        case .spanishLatam: return "CONFIGURACIÓN"
        case .french:       return "PARAMÈTRES"
        case .german:       return "EINSTELLUNGEN"
        case .hindi:        return "सेटिंग्स"
        case .arabic:       return "الإعدادات"
        case .russian:      return "НАСТРОЙКИ"
        case .polish:       return "USTAWIENIA"
        }
    }

    var languageLabel: String {
        switch self {
        case .english:      return "Language"
        case .portuguese:   return "Idioma"
        case .spanish:      return "Idioma"
        case .spanishLatam: return "Idioma"
        case .french:       return "Langue"
        case .german:       return "Sprache"
        case .hindi:        return "भाषा"
        case .arabic:       return "اللغة"
        case .russian:      return "Язык"
        case .polish:       return "Język"
        }
    }

    var notificationsLabel: String {
        switch self {
        case .english:      return "Notifications"
        case .portuguese:   return "Notificações"
        case .spanish:      return "Notificaciones"
        case .spanishLatam: return "Notificaciones"
        case .french:       return "Notifications"
        case .german:       return "Benachrichtigungen"
        case .hindi:        return "सूचनाएं"
        case .arabic:       return "إشعارات"
        case .russian:      return "Уведомления"
        case .polish:       return "Powiadomienia"
        }
    }

    var appearanceLabel: String {
        switch self {
        case .english:      return "Appearance"
        case .portuguese:   return "Aparência"
        case .spanish:      return "Apariencia"
        case .spanishLatam: return "Apariencia"
        case .french:       return "Apparence"
        case .german:       return "Erscheinungsbild"
        case .hindi:        return "दिखावट"
        case .arabic:       return "المظهر"
        case .russian:      return "Внешний вид"
        case .polish:       return "Wygląd"
        }
    }

    var manageSubscriptionLabel: String {
        switch self {
        case .english:      return "Manage Subscription"
        case .portuguese:   return "Gerenciar Assinatura"
        case .spanish:      return "Gestionar Suscripción"
        case .spanishLatam: return "Gestionar Suscripción"
        case .french:       return "Gérer l'abonnement"
        case .german:       return "Abonnement verwalten"
        case .hindi:        return "सदस्यता प्रबंधित करें"
        case .arabic:       return "إدارة الاشتراك"
        case .russian:      return "Управление подпиской"
        case .polish:       return "Zarządzaj subskrypcją"
        }
    }

    var privacyPolicyLabel: String {
        switch self {
        case .english:      return "Privacy Policy"
        case .portuguese:   return "Política de Privacidade"
        case .spanish:      return "Política de Privacidad"
        case .spanishLatam: return "Política de Privacidad"
        case .french:       return "Politique de confidentialité"
        case .german:       return "Datenschutzrichtlinie"
        case .hindi:        return "गोपनीयता नीति"
        case .arabic:       return "سياسة الخصوصية"
        case .russian:      return "Политика конфиденциальности"
        case .polish:       return "Polityka prywatności"
        }
    }

    var helpSupportLabel: String {
        switch self {
        case .english:      return "Help & Support"
        case .portuguese:   return "Ajuda e Suporte"
        case .spanish:      return "Ayuda y Soporte"
        case .spanishLatam: return "Ayuda y Soporte"
        case .french:       return "Aide et Support"
        case .german:       return "Hilfe & Support"
        case .hindi:        return "सहायता और समर्थन"
        case .arabic:       return "المساعدة والدعم"
        case .russian:      return "Помощь и Поддержка"
        case .polish:       return "Pomoc i Wsparcie"
        }
    }

    var logOutLabel: String {
        switch self {
        case .english:      return "Log Out"
        case .portuguese:   return "Sair"
        case .spanish:      return "Cerrar Sesión"
        case .spanishLatam: return "Cerrar Sesión"
        case .french:       return "Se déconnecter"
        case .german:       return "Abmelden"
        case .hindi:        return "लॉग आउट"
        case .arabic:       return "تسجيل الخروج"
        case .russian:      return "Выйти"
        case .polish:       return "Wyloguj"
        }
    }

    var foodPreferencesLabel: String {
        switch self {
        case .english:      return "Food Preferences"
        case .portuguese:   return "Preferências Alimentares"
        case .spanish:      return "Preferencias Alimentarias"
        case .spanishLatam: return "Preferencias Alimentarias"
        case .french:       return "Préférences alimentaires"
        case .german:       return "Ernährungsvorlieben"
        case .hindi:        return "खाद्य प्राथमिकताएं"
        case .arabic:       return "تفضيلات الطعام"
        case .russian:      return "Пищевые предпочтения"
        case .polish:       return "Preferencje żywieniowe"
        }
    }

    var myDocumentsLabel: String {
        switch self {
        case .english:      return "My Documents"
        case .portuguese:   return "Meus Documentos"
        case .spanish:      return "Mis Documentos"
        case .spanishLatam: return "Mis Documentos"
        case .french:       return "Mes Documents"
        case .german:       return "Meine Dokumente"
        case .hindi:        return "मेरे दस्तावेज़"
        case .arabic:       return "وثائقي"
        case .russian:      return "Мои документы"
        case .polish:       return "Moje dokumenty"
        }
    }

    var myWellbeingLabel: String {
        switch self {
        case .english:      return "My Wellbeing"
        case .portuguese:   return "Meu Bem-Estar"
        case .spanish:      return "Mi Bienestar"
        case .spanishLatam: return "Mi Bienestar"
        case .french:       return "Mon Bien-être"
        case .german:       return "Mein Wohlbefinden"
        case .hindi:        return "मेरा कल्याण"
        case .arabic:       return "رفاهيتي"
        case .russian:      return "Моё Благополучие"
        case .polish:       return "Moje Samopoczucie"
        }
    }

    var bypassHistoryLabel: String {
        switch self {
        case .english:      return "Bypass History"
        case .portuguese:   return "Histórico de Bypass"
        case .spanish:      return "Historial de Bypass"
        case .spanishLatam: return "Historial de Bypass"
        case .french:       return "Historique de contournement"
        case .german:       return "Bypass-Verlauf"
        case .hindi:        return "बायपास इतिहास"
        case .arabic:       return "تاريخ التجاوز"
        case .russian:      return "История объезда"
        case .polish:       return "Historia ominięcia"
        }
    }

    var myRatingsLabel: String {
        switch self {
        case .english:      return "My Ratings"
        case .portuguese:   return "Minhas Avaliações"
        case .spanish:      return "Mis Calificaciones"
        case .spanishLatam: return "Mis Calificaciones"
        case .french:       return "Mes Évaluations"
        case .german:       return "Meine Bewertungen"
        case .hindi:        return "मेरी रेटिंग"
        case .arabic:       return "تقييماتي"
        case .russian:      return "Мои оценки"
        case .polish:       return "Moje oceny"
        }
    }

    // MARK: - Common action labels
    var doneLabel: String {
        switch self {
        case .english:      return "Done"
        case .portuguese:   return "Concluído"
        case .spanish:      return "Listo"
        case .spanishLatam: return "Listo"
        case .french:       return "Terminé"
        case .german:       return "Fertig"
        case .hindi:        return "हो गया"
        case .arabic:       return "تم"
        case .russian:      return "Готово"
        case .polish:       return "Gotowe"
        }
    }

    var cancelLabel: String {
        switch self {
        case .english:      return "Cancel"
        case .portuguese:   return "Cancelar"
        case .spanish:      return "Cancelar"
        case .spanishLatam: return "Cancelar"
        case .french:       return "Annuler"
        case .german:       return "Abbrechen"
        case .hindi:        return "रद्द करें"
        case .arabic:       return "إلغاء"
        case .russian:      return "Отмена"
        case .polish:       return "Anuluj"
        }
    }

    var saveLabel: String {
        switch self {
        case .english:      return "Save"
        case .portuguese:   return "Salvar"
        case .spanish:      return "Guardar"
        case .spanishLatam: return "Guardar"
        case .french:       return "Enregistrer"
        case .german:       return "Speichern"
        case .hindi:        return "सहेजें"
        case .arabic:       return "حفظ"
        case .russian:      return "Сохранить"
        case .polish:       return "Zapisz"
        }
    }

    var searchLabel: String {
        switch self {
        case .english:      return "Search"
        case .portuguese:   return "Buscar"
        case .spanish:      return "Buscar"
        case .spanishLatam: return "Buscar"
        case .french:       return "Rechercher"
        case .german:       return "Suchen"
        case .hindi:        return "खोजें"
        case .arabic:       return "بحث"
        case .russian:      return "Поиск"
        case .polish:       return "Szukaj"
        }
    }

    // MARK: - Road Report labels
    var reportSectionParking: String {
        switch self {
        case .english:      return "PARKING"
        case .portuguese:   return "ESTACIONAMENTO"
        case .spanish:      return "ESTACIONAMIENTO"
        case .spanishLatam: return "ESTACIONAMIENTO"
        case .french:       return "STATIONNEMENT"
        case .german:       return "PARKEN"
        case .hindi:        return "पार्किंग"
        case .arabic:       return "مواقف"
        case .russian:      return "ПАРКОВКА"
        case .polish:       return "PARKING"
        }
    }

    var reportSectionWeigh: String {
        switch self {
        case .english:      return "WEIGH STATION"
        case .portuguese:   return "BALANÇA"
        case .spanish:      return "BÁSCULA"
        case .spanishLatam: return "BÁSCULA"
        case .french:       return "BALANCE"
        case .german:       return "WAAGE"
        case .hindi:        return "वज़न स्टेशन"
        case .arabic:       return "محطة الوزن"
        case .russian:      return "ВЕСОВАЯ"
        case .polish:       return "WAGA"
        }
    }

    var reportSectionAlerts: String {
        switch self {
        case .english:      return "ROAD ALERTS"
        case .portuguese:   return "ALERTAS DE ESTRADA"
        case .spanish:      return "ALERTAS DE RUTA"
        case .spanishLatam: return "ALERTAS DE RUTA"
        case .french:       return "ALERTES ROUTIÈRES"
        case .german:       return "STRASSENWARNUNGEN"
        case .hindi:        return "सड़क अलर्ट"
        case .arabic:       return "تنبيهات الطريق"
        case .russian:      return "ДОРОЖНЫЕ ПРЕДУПРЕЖДЕНИЯ"
        case .polish:       return "OSTRZEŻENIA DROGOWE"
        }
    }

    var recentReportsLabel: String {
        switch self {
        case .english:      return "RECENT REPORTS NEAR YOU"
        case .portuguese:   return "RELATÓRIOS RECENTES PERTO DE VOCÊ"
        case .spanish:      return "REPORTES RECIENTES CERCANOS"
        case .spanishLatam: return "REPORTES RECIENTES CERCANOS"
        case .french:       return "RAPPORTS RÉCENTS PRÈS DE VOUS"
        case .german:       return "AKTUELLE MELDUNGEN IN IHRER NÄHE"
        case .hindi:        return "आपके पास हाल की रिपोर्ट"
        case .arabic:       return "تقارير قريبة منك"
        case .russian:      return "НЕДАВНИЕ ОТЧЁТЫ РЯДОМ"
        case .polish:       return "OSTATNIE RAPORTY W POBLIŻU"
        }
    }

    // MARK: - Truck Signs labels
    var truckSignsTitle: String {
        switch self {
        case .english:      return "Truck Signs"
        case .portuguese:   return "Placas de Caminhão"
        case .spanish:      return "Señales de Camión"
        case .spanishLatam: return "Señales de Camión"
        case .french:       return "Panneaux Poids Lourds"
        case .german:       return "LKW-Schilder"
        case .hindi:        return "ट्रक संकेत"
        case .arabic:       return "لافتات الشاحنات"
        case .russian:      return "Знаки для грузовиков"
        case .polish:       return "Znaki dla ciężarówek"
        }
    }

    var searchSignsLabel: String {
        switch self {
        case .english:      return "Search truck signs"
        case .portuguese:   return "Buscar placas"
        case .spanish:      return "Buscar señales"
        case .spanishLatam: return "Buscar señales"
        case .french:       return "Rechercher des panneaux"
        case .german:       return "Schilder suchen"
        case .hindi:        return "ट्रक संकेत खोजें"
        case .arabic:       return "البحث عن اللافتات"
        case .russian:      return "Поиск знаков"
        case .polish:       return "Szukaj znaków"
        }
    }

    var reportInfoBanner: String {
        switch self {
        case .english:      return "Your reports help fellow drivers. Tap to submit at your current location."
        case .portuguese:   return "Seus relatórios ajudam outros motoristas. Toque para enviar na sua localização atual."
        case .spanish:      return "Tus informes ayudan a otros conductores. Toca para enviar en tu ubicación actual."
        case .spanishLatam: return "Tus informes ayudan a otros conductores. Toca para enviar en tu ubicación actual."
        case .french:       return "Vos rapports aident les autres conducteurs. Appuyez pour soumettre à votre emplacement actuel."
        case .german:       return "Ihre Berichte helfen anderen Fahrern. Tippen zum Senden am aktuellen Standort."
        case .hindi:        return "आपकी रिपोर्ट साथी चालकों की मदद करती है। अपनी वर्तमान स्थान पर सबमिट करने के लिए टैप करें।"
        case .arabic:       return "تقاريرك تساعد السائقين الآخرين. اضغط للإرسال من موقعك الحالي."
        case .russian:      return "Ваши отчёты помогают другим водителям. Нажмите для отправки с вашего текущего местоположения."
        case .polish:       return "Twoje raporty pomagają innym kierowcom. Dotknij, aby wysłać ze swojej aktualnej lokalizacji."
        }
    }

    var allCategoryLabel: String {
        switch self {
        case .english:      return "All"
        case .portuguese:   return "Todos"
        case .spanish:      return "Todo"
        case .spanishLatam: return "Todo"
        case .french:       return "Tout"
        case .german:       return "Alle"
        case .hindi:        return "सभी"
        case .arabic:       return "الكل"
        case .russian:      return "Все"
        case .polish:       return "Wszystkie"
        }
    }

    var myProfileTitle: String {
        switch self {
        case .english:      return "My Profile"
        case .portuguese:   return "Meu Perfil"
        case .spanish:      return "Mi Perfil"
        case .spanishLatam: return "Mi Perfil"
        case .french:       return "Mon Profil"
        case .german:       return "Mein Profil"
        case .hindi:        return "मेरी प्रोफ़ाइल"
        case .arabic:       return "ملفي الشخصي"
        case .russian:      return "Мой профиль"
        case .polish:       return "Mój profil"
        }
    }

    var reportsStatLabel: String {
        switch self {
        case .english:      return "Reports"
        case .portuguese:   return "Relatórios"
        case .spanish:      return "Informes"
        case .spanishLatam: return "Informes"
        case .french:       return "Rapports"
        case .german:       return "Berichte"
        case .hindi:        return "रिपोर्ट"
        case .arabic:       return "التقارير"
        case .russian:      return "Отчёты"
        case .polish:       return "Raporty"
        }
    }

    var reviewsStatLabel: String {
        switch self {
        case .english:      return "Reviews"
        case .portuguese:   return "Avaliações"
        case .spanish:      return "Reseñas"
        case .spanishLatam: return "Reseñas"
        case .french:       return "Avis"
        case .german:       return "Bewertungen"
        case .hindi:        return "समीक्षाएं"
        case .arabic:       return "المراجعات"
        case .russian:      return "Отзывы"
        case .polish:       return "Recenzje"
        }
    }

    var messagesStatLabel: String {
        switch self {
        case .english:      return "Messages"
        case .portuguese:   return "Mensagens"
        case .spanish:      return "Mensajes"
        case .spanishLatam: return "Mensajes"
        case .french:       return "Messages"
        case .german:       return "Nachrichten"
        case .hindi:        return "संदेश"
        case .arabic:       return "الرسائل"
        case .russian:      return "Сообщения"
        case .polish:       return "Wiadomości"
        }
    }

    var logOutConfirmTitle: String {
        switch self {
        case .english:      return "Log Out"
        case .portuguese:   return "Sair"
        case .spanish:      return "Cerrar sesión"
        case .spanishLatam: return "Cerrar sesión"
        case .french:       return "Se déconnecter"
        case .german:       return "Abmelden"
        case .hindi:        return "लॉग आउट"
        case .arabic:       return "تسجيل الخروج"
        case .russian:      return "Выйти"
        case .polish:       return "Wyloguj się"
        }
    }

    var logOutConfirmMessage: String {
        switch self {
        case .english:      return "Are you sure you want to log out?"
        case .portuguese:   return "Tem certeza que deseja sair?"
        case .spanish:      return "¿Estás seguro de que quieres cerrar sesión?"
        case .spanishLatam: return "¿Estás seguro de que quieres cerrar sesión?"
        case .french:       return "Êtes-vous sûr de vouloir vous déconnecter?"
        case .german:       return "Sind Sie sicher, dass Sie sich abmelden möchten?"
        case .hindi:        return "क्या आप वाकई लॉग आउट करना चाहते हैं?"
        case .arabic:       return "هل أنت متأكد أنك تريد تسجيل الخروج؟"
        case .russian:      return "Вы уверены, что хотите выйти?"
        case .polish:       return "Czy na pewno chcesz się wylogować?"
        }
    }

    var expiredLabel: String {
        switch self {
        case .english:      return "EXPIRED"
        case .portuguese:   return "VENCIDO"
        case .spanish:      return "VENCIDO"
        case .spanishLatam: return "VENCIDO"
        case .french:       return "EXPIRÉ"
        case .german:       return "ABGELAUFEN"
        case .hindi:        return "समाप्त"
        case .arabic:       return "منتهي الصلاحية"
        case .russian:      return "ПРОСРОЧЕН"
        case .polish:       return "WYGASŁY"
        }
    }

    var noExpiryLabel: String {
        switch self {
        case .english:      return "No expiry"
        case .portuguese:   return "Sem vencimento"
        case .spanish:      return "Sin vencimiento"
        case .spanishLatam: return "Sin vencimiento"
        case .french:       return "Sans expiration"
        case .german:       return "Kein Ablauf"
        case .hindi:        return "कोई समाप्ति नहीं"
        case .arabic:       return "لا انتهاء صلاحية"
        case .russian:      return "Без истечения"
        case .polish:       return "Brak wygaśnięcia"
        }
    }

    var noExpirationSetLabel: String {
        switch self {
        case .english:      return "No expiration set"
        case .portuguese:   return "Sem data de vencimento"
        case .spanish:      return "Sin fecha de vencimiento"
        case .spanishLatam: return "Sin fecha de vencimiento"
        case .french:       return "Pas de date d'expiration"
        case .german:       return "Kein Ablaufdatum festgelegt"
        case .hindi:        return "कोई समाप्ति तिथि निर्धारित नहीं"
        case .arabic:       return "لم يتم تحديد تاريخ انتهاء الصلاحية"
        case .russian:      return "Дата истечения не установлена"
        case .polish:       return "Brak ustawionej daty wygaśnięcia"
        }
    }

    var addFirstDocumentLabel: String {
        switch self {
        case .english:      return "Add First Document"
        case .portuguese:   return "Adicionar Primeiro Documento"
        case .spanish:      return "Agregar Primer Documento"
        case .spanishLatam: return "Agregar Primer Documento"
        case .french:       return "Ajouter le Premier Document"
        case .german:       return "Erstes Dokument hinzufügen"
        case .hindi:        return "पहला दस्तावेज़ जोड़ें"
        case .arabic:       return "إضافة أول مستند"
        case .russian:      return "Добавить первый документ"
        case .polish:       return "Dodaj pierwszy dokument"
        }
    }

    var vaultEmptySubtitle: String {
        switch self {
        case .english:      return "Add your CDL, Medical Card, DOT and insurance documents to get expiry alerts"
        case .portuguese:   return "Adicione seu CDL, Carteira de Saúde, DOT e documentos de seguro para receber alertas de vencimento"
        case .spanish:      return "Agrega tu CDL, Tarjeta Médica, DOT y documentos de seguro para recibir alertas de vencimiento"
        case .spanishLatam: return "Agrega tu CDL, Tarjeta Médica, DOT y documentos de seguro para recibir alertas de vencimiento"
        case .french:       return "Ajoutez votre CDL, carte médicale, DOT et documents d'assurance pour recevoir des alertes d'expiration"
        case .german:       return "Fügen Sie Ihren CDL, Krankenkarte, DOT und Versicherungsdokumente hinzu, um Ablaufwarnungen zu erhalten"
        case .hindi:        return "समाप्ति अलर्ट पाने के लिए अपना CDL, मेडिकल कार्ड, DOT और बीमा दस्तावेज़ जोड़ें"
        case .arabic:       return "أضف CDL وبطاقة طبية و DOT ووثائق التأمين للحصول على تنبيهات انتهاء الصلاحية"
        case .russian:      return "Добавьте CDL, медицинскую карту, DOT и страховые документы для получения уведомлений об истечении срока"
        case .polish:       return "Dodaj swój CDL, kartę medyczną, DOT i dokumenty ubezpieczeniowe, aby otrzymywać alerty o wygaśnięciu"
        }
    }

    var truckSignsGuideLabel: String {
        switch self {
        case .english:      return "Truck Signs Guide"
        case .portuguese:   return "Guia de Placas"
        case .spanish:      return "Guía de Señales"
        case .spanishLatam: return "Guía de Señales"
        case .french:       return "Guide des Panneaux"
        case .german:       return "LKW-Schilderführer"
        case .hindi:        return "ट्रक साइन गाइड"
        case .arabic:       return "دليل لافتات الشاحنات"
        case .russian:      return "Справочник знаков"
        case .polish:       return "Przewodnik po znakach"
        }
    }

    var truckSignsGuideSubtitle: String {
        switch self {
        case .english:      return "Restrictions, weigh stations, hazards & more"
        case .portuguese:   return "Restrições, postos de pesagem, perigos e mais"
        case .spanish:      return "Restricciones, básculas, peligros y más"
        case .spanishLatam: return "Restricciones, básculas, peligros y más"
        case .french:       return "Restrictions, stations de pesage, dangers et plus"
        case .german:       return "Einschränkungen, Wiegestationen, Gefahren & mehr"
        case .hindi:        return "प्रतिबंध, वजन केंद्र, खतरे और अधिक"
        case .arabic:       return "القيود ومحطات الوزن والمخاطر والمزيد"
        case .russian:      return "Ограничения, весовые станции, опасности и многое другое"
        case .polish:       return "Ograniczenia, stacje ważenia, zagrożenia i więcej"
        }
    }

    var wellnessSubtitle: String {
        switch self {
        case .english:      return "Health check-ins & medication reminders"
        case .portuguese:   return "Check-ins de saúde e lembretes de medicamentos"
        case .spanish:      return "Controles de salud y recordatorios de medicación"
        case .spanishLatam: return "Controles de salud y recordatorios de medicación"
        case .french:       return "Bilans de santé et rappels de médicaments"
        case .german:       return "Gesundheits-Check-ins und Medikatmentenerinnerungen"
        case .hindi:        return "स्वास्थ्य जांच और दवा अनुस्मारक"
        case .arabic:       return "فحوصات صحية وتذكيرات بالأدوية"
        case .russian:      return "Медицинские чек-ины и напоминания о лекарствах"
        case .polish:       return "Kontrole zdrowia i przypomnienia o lekach"
        }
    }

    var foodSectionSubtitle: String {
        switch self {
        case .english:      return "Diet type, allergies & restrictions"
        case .portuguese:   return "Tipo de dieta, alergias e restrições"
        case .spanish:      return "Tipo de dieta, alergias y restricciones"
        case .spanishLatam: return "Tipo de dieta, alergias y restricciones"
        case .french:       return "Type de régime, allergies et restrictions"
        case .german:       return "Diättyp, Allergien & Einschränkungen"
        case .hindi:        return "आहार प्रकार, एलर्जी और प्रतिबंध"
        case .arabic:       return "نوع النظام الغذائي والحساسية والقيود"
        case .russian:      return "Тип диеты, аллергии и ограничения"
        case .polish:       return "Typ diety, alergie i ograniczenia"
        }
    }

    var favoriteMealsLabel: String {
        switch self {
        case .english:      return "Favorite Meals"
        case .portuguese:   return "Refeições Favoritas"
        case .spanish:      return "Comidas Favoritas"
        case .spanishLatam: return "Comidas Favoritas"
        case .french:       return "Repas Favoris"
        case .german:       return "Lieblingsgerichte"
        case .hindi:        return "पसंदीदा भोजन"
        case .arabic:       return "الوجبات المفضلة"
        case .russian:      return "Любимые блюда"
        case .polish:       return "Ulubione posiłki"
        }
    }

    var favoriteMealsSubtitle: String {
        switch self {
        case .english:      return "Your saved meal picks at truck stops"
        case .portuguese:   return "Suas refeições favoritas em postos de parada"
        case .spanish:      return "Tus elecciones de comidas guardadas en paradas"
        case .spanishLatam: return "Tus elecciones de comidas guardadas en paradas"
        case .french:       return "Vos choix de repas enregistrés aux arrêts"
        case .german:       return "Ihre gespeicherten Mahlzeitenauswahl an Raststätten"
        case .hindi:        return "ट्रक स्टॉप पर आपकी सहेजी गई भोजन पसंद"
        case .arabic:       return "اختيارات الوجبات المحفوظة في محطات الشاحنات"
        case .russian:      return "Ваши сохранённые блюда на стоянках"
        case .polish:       return "Twoje zapisane wybory posiłków na postojach"
        }
    }

    var stopAdvisorFoodLabel: String {
        switch self {
        case .english:      return "Stop Advisor — Food"
        case .portuguese:   return "Consultor de Paradas — Alimentação"
        case .spanish:      return "Asesor de Paradas — Comida"
        case .spanishLatam: return "Asesor de Paradas — Comida"
        case .french:       return "Conseiller d'arrêts — Restauration"
        case .german:       return "Halt-Berater — Essen"
        case .hindi:        return "स्टॉप सलाहकार — भोजन"
        case .arabic:       return "مستشار التوقف — الطعام"
        case .russian:      return "Советник остановок — Еда"
        case .polish:       return "Doradca postojów — Jedzenie"
        }
    }

    var stopAdvisorSubtitle: String {
        switch self {
        case .english:      return "Suggestions based on your profile"
        case .portuguese:   return "Sugestões baseadas no seu perfil"
        case .spanish:      return "Sugerencias basadas en tu perfil"
        case .spanishLatam: return "Sugerencias basadas en tu perfil"
        case .french:       return "Suggestions basées sur votre profil"
        case .german:       return "Vorschläge basierend auf Ihrem Profil"
        case .hindi:        return "आपकी प्रोफ़ाइल पर आधारित सुझाव"
        case .arabic:       return "اقتراحات بناءً على ملفك الشخصي"
        case .russian:      return "Предложения на основе вашего профиля"
        case .polish:       return "Sugestie oparte na Twoim profilu"
        }
    }

    var bypassHistorySubtitle: String {
        switch self {
        case .english:      return "Weigh station bypass records"
        case .portuguese:   return "Registros de bypass de postos de pesagem"
        case .spanish:      return "Registros de bypass de básculas"
        case .spanishLatam: return "Registros de bypass de básculas"
        case .french:       return "Registres de contournement des stations de pesage"
        case .german:       return "Umgehungsaufzeichnungen der Wiegestation"
        case .hindi:        return "वजन स्टेशन बाईपास रिकॉर्ड"
        case .arabic:       return "سجلات تجاوز محطة الوزن"
        case .russian:      return "Записи объезда весовых станций"
        case .polish:       return "Rekordy ominięcia stacji ważenia"
        }
    }

    var myRatingsSubtitle: String {
        switch self {
        case .english:      return "Truck stop & facility reviews you've left"
        case .portuguese:   return "Avaliações de postos e instalações que você deixou"
        case .spanish:      return "Reseñas de paradas y servicios que has dejado"
        case .spanishLatam: return "Reseñas de paradas y servicios que has dejado"
        case .french:       return "Avis sur les arrêts et installations que vous avez laissés"
        case .german:       return "Ihre hinterlassenen Bewertungen zu Raststätten"
        case .hindi:        return "आपके छोड़े गए ट्रक स्टॉप और सुविधा समीक्षाएं"
        case .arabic:       return "مراجعاتك لمحطات الشاحنات والمرافق"
        case .russian:      return "Ваши отзывы о стоянках и объектах"
        case .polish:       return "Twoje oceny stacji i obiektów"
        }
    }

    var stopAdvisorLabel: String {
        switch self {
        case .english:      return "Stop Advisor"
        case .portuguese:   return "Consultor de Paradas"
        case .spanish:      return "Asesor de Paradas"
        case .spanishLatam: return "Asesor de Paradas"
        case .french:       return "Conseiller d'arrêts"
        case .german:       return "Halt-Berater"
        case .hindi:        return "स्टॉप सलाहकार"
        case .arabic:       return "مستشار التوقف"
        case .russian:      return "Советник остановок"
        case .polish:       return "Doradca postojów"
        }
    }

    var smartStopSubtitle: String {
        switch self {
        case .english:      return "Smart stop recommendations"
        case .portuguese:   return "Recomendações inteligentes de paradas"
        case .spanish:      return "Recomendaciones inteligentes de paradas"
        case .spanishLatam: return "Recomendaciones inteligentes de paradas"
        case .french:       return "Recommandations d'arrêts intelligentes"
        case .german:       return "Intelligente Haltempfehlungen"
        case .hindi:        return "स्मार्ट स्टॉप सिफारिशें"
        case .arabic:       return "توصيات توقف ذكية"
        case .russian:      return "Умные рекомендации по остановкам"
        case .polish:       return "Inteligentne rekomendacje postojów"
        }
    }

    var facilityRatingLabel: String {
        switch self {
        case .english:      return "Facility Rating"
        case .portuguese:   return "Avaliação de Instalação"
        case .spanish:      return "Calificación de Instalación"
        case .spanishLatam: return "Calificación de Instalación"
        case .french:       return "Évaluation des installations"
        case .german:       return "Einrichtungsbewertung"
        case .hindi:        return "सुविधा रेटिंग"
        case .arabic:       return "تقييم المنشأة"
        case .russian:      return "Оценка объекта"
        case .polish:       return "Ocena obiektu"
        }
    }

    var facilityRatingSubtitle: String {
        switch self {
        case .english:      return "Rate truck stops & services"
        case .portuguese:   return "Avalie postos e serviços"
        case .spanish:      return "Califica paradas y servicios"
        case .spanishLatam: return "Califica paradas y servicios"
        case .french:       return "Évaluez les arrêts et services"
        case .german:       return "Raststätten & Services bewerten"
        case .hindi:        return "ट्रक स्टॉप और सेवाओं को रेट करें"
        case .arabic:       return "قيّم محطات الشاحنات والخدمات"
        case .russian:      return "Оцените стоянки и сервисы"
        case .polish:       return "Oceń stacje i usługi"
        }
    }

    var myDocumentsSubtitle: String {
        switch self {
        case .english:      return "CDL, medical card & certifications"
        case .portuguese:   return "CDL, carteira de saúde e certificações"
        case .spanish:      return "CDL, tarjeta médica y certificaciones"
        case .spanishLatam: return "CDL, tarjeta médica y certificaciones"
        case .french:       return "CDL, carte médicale et certifications"
        case .german:       return "CDL, Krankenkarte & Zertifizierungen"
        case .hindi:        return "CDL, मेडिकल कार्ड और प्रमाणन"
        case .arabic:       return "CDL وبطاقة طبية وشهادات"
        case .russian:      return "CDL, медицинская карта и сертификаты"
        case .polish:       return "CDL, karta medyczna i certyfikaty"
        }
    }

    var findDMVLabel: String {
        switch self {
        case .english:      return "Find DMV"
        case .portuguese:   return "Encontrar DETRAN"
        case .spanish:      return "Buscar DMV"
        case .spanishLatam: return "Buscar DMV"
        case .french:       return "Trouver la DMV"
        case .german:       return "Führerscheinstelle finden"
        case .hindi:        return "DMV खोजें"
        case .arabic:       return "البحث عن DMV"
        case .russian:      return "Найти ГИБДД"
        case .polish:       return "Znajdź DMV"
        }
    }

    var findDMVSubtitle: String {
        switch self {
        case .english:      return "Locate nearby DMV offices"
        case .portuguese:   return "Localizar DESTRANs próximos"
        case .spanish:      return "Localizar oficinas DMV cercanas"
        case .spanishLatam: return "Localizar oficinas DMV cercanas"
        case .french:       return "Localiser les bureaux DMV à proximité"
        case .german:       return "Führerscheinstellen in der Nähe finden"
        case .hindi:        return "निकटवर्ती DMV कार्यालय खोजें"
        case .arabic:       return "تحديد مكاتب DMV القريبة"
        case .russian:      return "Найти ближайшие отделения ГИБДД"
        case .polish:       return "Znajdź pobliskie biura DMV"
        }
    }

    var drugTestLabel: String {
        switch self {
        case .english:      return "Drug Test & Medical Card"
        case .portuguese:   return "Teste de Drogas e Carteira de Saúde"
        case .spanish:      return "Prueba de Drogas y Tarjeta Médica"
        case .spanishLatam: return "Prueba de Drogas y Tarjeta Médica"
        case .french:       return "Test de drogues et carte médicale"
        case .german:       return "Drogentest & Krankenkarte"
        case .hindi:        return "ड्रग टेस्ट और मेडिकल कार्ड"
        case .arabic:       return "فحص المخدرات والبطاقة الطبية"
        case .russian:      return "Тест на наркотики и медицинская карта"
        case .polish:       return "Test na narkotyki i karta medyczna"
        }
    }

    var drugTestSubtitle: String {
        switch self {
        case .english:      return "Test centers & expiry reminders"
        case .portuguese:   return "Centros de teste e lembretes de vencimento"
        case .spanish:      return "Centros de prueba y recordatorios de vencimiento"
        case .spanishLatam: return "Centros de prueba y recordatorios de vencimiento"
        case .french:       return "Centres de test et rappels d'expiration"
        case .german:       return "Testzentren & Ablauferinnerungen"
        case .hindi:        return "परीक्षण केंद्र और समाप्ति अनुस्मारक"
        case .arabic:       return "مراكز الاختبار وتذكيرات انتهاء الصلاحية"
        case .russian:      return "Тест-центры и напоминания об истечении срока"
        case .polish:       return "Centra testowe i przypomnienia o wygaśnięciu"
        }
    }

    var manageSubscriptionSubtitle: String {
        switch self {
        case .english:      return "View or upgrade your plan"
        case .portuguese:   return "Ver ou atualizar seu plano"
        case .spanish:      return "Ver o actualizar tu plan"
        case .spanishLatam: return "Ver o actualizar tu plan"
        case .french:       return "Voir ou mettre à niveau votre plan"
        case .german:       return "Plan anzeigen oder upgraden"
        case .hindi:        return "अपना प्लान देखें या अपग्रेड करें"
        case .arabic:       return "عرض أو ترقية خطتك"
        case .russian:      return "Просмотр или обновление плана"
        case .polish:       return "Przeglądaj lub aktualizuj swój plan"
        }
    }

    var privacyPolicySubtitle: String {
        switch self {
        case .english:      return "How we protect your data"
        case .portuguese:   return "Como protegemos seus dados"
        case .spanish:      return "Cómo protegemos tus datos"
        case .spanishLatam: return "Cómo protegemos tus datos"
        case .french:       return "Comment nous protégeons vos données"
        case .german:       return "Wie wir Ihre Daten schützen"
        case .hindi:        return "हम आपके डेटा की सुरक्षा कैसे करते हैं"
        case .arabic:       return "كيف نحمي بياناتك"
        case .russian:      return "Как мы защищаем ваши данные"
        case .polish:       return "Jak chronimy Twoje dane"
        }
    }

    var helpSupportSubtitle: String {
        switch self {
        case .english:      return "FAQs, contact & bug reports"
        case .portuguese:   return "FAQs, contato e relatórios de bugs"
        case .spanish:      return "Preguntas frecuentes, contacto e informes de errores"
        case .spanishLatam: return "Preguntas frecuentes, contacto e informes de errores"
        case .french:       return "FAQ, contact et rapports de bogues"
        case .german:       return "FAQ, Kontakt & Fehlerberichte"
        case .hindi:        return "FAQ, संपर्क और बग रिपोर्ट"
        case .arabic:       return "الأسئلة الشائعة والتواصل وتقارير الأخطاء"
        case .russian:      return "ЧЗВ, контакт и сообщения об ошибках"
        case .polish:       return "FAQ, kontakt i raporty błędów"
        }
    }

    var autoLabel: String {
        switch self {
        case .english:      return "Auto"
        case .portuguese:   return "Auto"
        case .spanish:      return "Auto"
        case .spanishLatam: return "Auto"
        case .french:       return "Auto"
        case .german:       return "Auto"
        case .hindi:        return "स्वतः"
        case .arabic:       return "تلقائي"
        case .russian:      return "Авто"
        case .polish:       return "Auto"
        }
    }

    var lightLabel: String {
        switch self {
        case .english:      return "Light"
        case .portuguese:   return "Claro"
        case .spanish:      return "Claro"
        case .spanishLatam: return "Claro"
        case .french:       return "Clair"
        case .german:       return "Hell"
        case .hindi:        return "हल्का"
        case .arabic:       return "فاتح"
        case .russian:      return "Светлая"
        case .polish:       return "Jasny"
        }
    }

    var darkLabel: String {
        switch self {
        case .english:      return "Dark"
        case .portuguese:   return "Escuro"
        case .spanish:      return "Oscuro"
        case .spanishLatam: return "Oscuro"
        case .french:       return "Sombre"
        case .german:       return "Dunkel"
        case .hindi:        return "गहरा"
        case .arabic:       return "داكن"
        case .russian:      return "Тёмная"
        case .polish:       return "Ciemny"
        }
    }

    var driverTipsTitle: String {
        switch self {
        case .english:      return "Driver Tips"
        case .portuguese:   return "Dicas para Motoristas"
        case .spanish:      return "Consejos para Conductores"
        case .spanishLatam: return "Consejos para Conductores"
        case .french:       return "Conseils du Conducteur"
        case .german:       return "Fahrertipps"
        case .hindi:        return "चालक सुझाव"
        case .arabic:       return "نصائح السائق"
        case .russian:      return "Советы водителю"
        case .polish:       return "Wskazówki dla kierowcy"
        }
    }

    var reportSubmittedTitle: String {
        switch self {
        case .english:      return "Report Submitted!"
        case .portuguese:   return "Alerta Enviado!"
        case .spanish:      return "¡Reporte Enviado!"
        case .spanishLatam: return "¡Reporte Enviado!"
        case .french:       return "Signalement envoyé !"
        case .german:       return "Meldung gesendet!"
        case .hindi:        return "रिपोर्ट सबमिट हुई!"
        case .arabic:       return "تم إرسال التقرير!"
        case .russian:      return "Сообщение отправлено!"
        case .polish:       return "Zgłoszenie wysłane!"
        }
    }

    var reportSubmittedMessage: String {
        switch self {
        case .english:      return "Thank you for keeping drivers safe!"
        case .portuguese:   return "Obrigado por manter os motoristas seguros!"
        case .spanish:      return "¡Gracias por mantener a los conductores seguros!"
        case .spanishLatam: return "¡Gracias por mantener a los conductores seguros!"
        case .french:       return "Merci de contribuer à la sécurité des conducteurs !"
        case .german:       return "Danke, dass du Fahrer sicher hältst!"
        case .hindi:        return "चालकों को सुरक्षित रखने में मदद करने के लिए धन्यवाद!"
        case .arabic:       return "شكراً لمساعدتك في إبقاء السائقين بأمان!"
        case .russian:      return "Спасибо за заботу о безопасности водителей!"
        case .polish:       return "Dziękujemy za dbanie o bezpieczeństwo kierowców!"
        }
    }

    // Report type names
    var reportParkingFull: String {
        switch self {
        case .english:      return "Parking Full"
        case .portuguese:   return "Estac. Lotado"
        case .spanish:      return "Parque Lleno"
        case .spanishLatam: return "Parque Lleno"
        case .french:       return "Parking Plein"
        case .german:       return "Parkplatz Voll"
        case .hindi:        return "पार्किंग भरी"
        case .arabic:       return "الموقف ممتلئ"
        case .russian:      return "Парковка полна"
        case .polish:       return "Parking Pełny"
        }
    }

    var reportParkingAvailable: String {
        switch self {
        case .english:      return "Parking Open"
        case .portuguese:   return "Estac. Livre"
        case .spanish:      return "Parque Libre"
        case .spanishLatam: return "Parque Libre"
        case .french:       return "Parking Libre"
        case .german:       return "Parkplatz Frei"
        case .hindi:        return "पार्किंग उपलब्ध"
        case .arabic:       return "موقف متاح"
        case .russian:      return "Парковка свободна"
        case .polish:       return "Parking Wolny"
        }
    }

    var reportScaleOpen: String {
        switch self {
        case .english:      return "Scale Open"
        case .portuguese:   return "Balança Aberta"
        case .spanish:      return "Báscula Abierta"
        case .spanishLatam: return "Báscula Abierta"
        case .french:       return "Balance Ouverte"
        case .german:       return "Waage Offen"
        case .hindi:        return "तराजू खुला"
        case .arabic:       return "الميزان مفتوح"
        case .russian:      return "Весы открыты"
        case .polish:       return "Waga Otwarta"
        }
    }

    var reportScaleClosed: String {
        switch self {
        case .english:      return "Scale Closed"
        case .portuguese:   return "Balança Fechada"
        case .spanish:      return "Báscula Cerrada"
        case .spanishLatam: return "Báscula Cerrada"
        case .french:       return "Balance Fermée"
        case .german:       return "Waage Geschlossen"
        case .hindi:        return "तराजू बंद"
        case .arabic:       return "الميزان مغلق"
        case .russian:      return "Весы закрыты"
        case .polish:       return "Waga Zamknięta"
        }
    }

    var reportHazard: String {
        switch self {
        case .english:      return "Safety Hazard"
        case .portuguese:   return "Risco de Segurança"
        case .spanish:      return "Peligro en Ruta"
        case .spanishLatam: return "Peligro en Ruta"
        case .french:       return "Danger Sécurité"
        case .german:       return "Sicherheitsgefahr"
        case .hindi:        return "सुरक्षा खतरा"
        case .arabic:       return "خطر أمني"
        case .russian:      return "Опасность"
        case .polish:       return "Zagrożenie"
        }
    }

    var reportRoadCondition: String {
        switch self {
        case .english:      return "Road Condition"
        case .portuguese:   return "Condição da Pista"
        case .spanish:      return "Cond. de Camino"
        case .spanishLatam: return "Cond. de Camino"
        case .french:       return "État de la Route"
        case .german:       return "Straßenzustand"
        case .hindi:        return "सड़क की स्थिति"
        case .arabic:       return "حالة الطريق"
        case .russian:      return "Состояние дороги"
        case .polish:       return "Stan Drogi"
        }
    }

    var reportMechanical: String {
        switch self {
        case .english:      return "Breakdown"
        case .portuguese:   return "Pane Mecânica"
        case .spanish:      return "Avería"
        case .spanishLatam: return "Avería"
        case .french:       return "Panne"
        case .german:       return "Panne"
        case .hindi:        return "यांत्रिक खराबी"
        case .arabic:       return "عطل ميكانيكي"
        case .russian:      return "Поломка"
        case .polish:       return "Awaria"
        }
    }

    var reportPolice: String {
        switch self {
        case .english:      return "Police Activity"
        case .portuguese:   return "Fiscalização"
        case .spanish:      return "Actividad Policial"
        case .spanishLatam: return "Actividad Policial"
        case .french:       return "Activité Policière"
        case .german:       return "Polizei Aktivität"
        case .hindi:        return "पुलिस गतिविधि"
        case .arabic:       return "نشاط شرطي"
        case .russian:      return "Полиция"
        case .polish:       return "Aktywność Policji"
        }
    }

    // Report subtitles
    var reportSubParkingFull: String {
        switch self {
        case .english:      return "No spaces available"
        case .portuguese:   return "Sem vagas disponíveis"
        case .spanish:      return "Sin espacios disponibles"
        case .spanishLatam: return "Sin espacios disponibles"
        case .french:       return "Pas de place disponible"
        case .german:       return "Kein Platz verfügbar"
        case .hindi:        return "कोई जगह उपलब्ध नहीं"
        case .arabic:       return "لا توجد أماكن متاحة"
        case .russian:      return "Мест нет"
        case .polish:       return "Brak wolnych miejsc"
        }
    }

    var reportSubParkingAvailable: String {
        switch self {
        case .english:      return "Spaces open now"
        case .portuguese:   return "Vagas disponíveis"
        case .spanish:      return "Espacios disponibles"
        case .spanishLatam: return "Espacios disponibles"
        case .french:       return "Places disponibles"
        case .german:       return "Plätze verfügbar"
        case .hindi:        return "जगह उपलब्ध है"
        case .arabic:       return "توجد أماكن متاحة"
        case .russian:      return "Места есть"
        case .polish:       return "Miejsca dostępne"
        }
    }

    var reportSubScaleOpen: String {
        switch self {
        case .english:      return "Trucks must enter"
        case .portuguese:   return "Caminhões devem entrar"
        case .spanish:      return "Camiones deben entrar"
        case .spanishLatam: return "Camiones deben entrar"
        case .french:       return "Camions doivent entrer"
        case .german:       return "LKW müssen einfahren"
        case .hindi:        return "ट्रक को प्रवेश करना होगा"
        case .arabic:       return "يجب على الشاحنات الدخول"
        case .russian:      return "Грузовики обязаны въезжать"
        case .polish:       return "Ciężarówki muszą wjechać"
        }
    }

    var reportSubScaleClosed: String {
        switch self {
        case .english:      return "Bypass freely"
        case .portuguese:   return "Pode ignorar"
        case .spanish:      return "Puede omitir"
        case .spanishLatam: return "Puede omitir"
        case .french:       return "Passage libre"
        case .german:       return "Frei passieren"
        case .hindi:        return "स्वतंत्र रूप से जाएं"
        case .arabic:       return "المرور بحرية"
        case .russian:      return "Проезжайте свободно"
        case .polish:       return "Swobodny przejazd"
        }
    }

    var reportSubHazard: String {
        switch self {
        case .english:      return "Debris, ice, accident"
        case .portuguese:   return "Destroços, gelo, acidente"
        case .spanish:      return "Escombros, hielo, accidente"
        case .spanishLatam: return "Escombros, hielo, accidente"
        case .french:       return "Débris, glace, accident"
        case .german:       return "Trümmer, Eis, Unfall"
        case .hindi:        return "मलबा, बर्फ, दुर्घटना"
        case .arabic:       return "حطام، جليد، حادث"
        case .russian:      return "Обломки, лёд, авария"
        case .polish:       return "Gruz, lód, wypadek"
        }
    }

    var reportSubRoadCondition: String {
        switch self {
        case .english:      return "Weather, construction"
        case .portuguese:   return "Clima, obras"
        case .spanish:      return "Clima, construcción"
        case .spanishLatam: return "Clima, construcción"
        case .french:       return "Météo, travaux"
        case .german:       return "Wetter, Baustelle"
        case .hindi:        return "मौसम, निर्माण"
        case .arabic:       return "طقس، أعمال بناء"
        case .russian:      return "Погода, стройка"
        case .polish:       return "Pogoda, roboty drogowe"
        }
    }

    var reportSubMechanical: String {
        switch self {
        case .english:      return "Breakdown, tire issue"
        case .portuguese:   return "Pane, problema de pneu"
        case .spanish:      return "Avería, problemas de llanta"
        case .spanishLatam: return "Avería, problemas de llanta"
        case .french:       return "Panne, problème de pneu"
        case .german:       return "Panne, Reifenproblem"
        case .hindi:        return "खराबी, टायर की समस्या"
        case .arabic:       return "عطل، مشكلة في الإطار"
        case .russian:      return "Поломка, проблема с шиной"
        case .polish:       return "Awaria, problem z oponą"
        }
    }

    var reportSubPolice: String {
        switch self {
        case .english:      return "Enforcement activity"
        case .portuguese:   return "Fiscalização ativa"
        case .spanish:      return "Actividad de control"
        case .spanishLatam: return "Actividad de control"
        case .french:       return "Contrôle en cours"
        case .german:       return "Kontrolle aktiv"
        case .hindi:        return "प्रवर्तन गतिविधि"
        case .arabic:       return "نشاط إنفاذ القانون"
        case .russian:      return "Дежурство"
        case .polish:       return "Aktywna kontrola"
        }
    }

    var nextStepLabel: String {
        switch self {
        case .english:      return "Next →"
        case .portuguese:   return "Próximo →"
        case .spanish:      return "Siguiente →"
        case .spanishLatam: return "Siguiente →"
        case .french:       return "Suivant →"
        case .german:       return "Weiter →"
        case .hindi:        return "अगला →"
        case .arabic:       return "التالي →"
        case .russian:      return "Далее →"
        case .polish:       return "Dalej →"
        }
    }

    var skipForNowLabel: String {
        switch self {
        case .english:      return "Skip for now"
        case .portuguese:   return "Pular por agora"
        case .spanish:      return "Omitir por ahora"
        case .spanishLatam: return "Omitir por ahora"
        case .french:       return "Ignorer pour l'instant"
        case .german:       return "Jetzt überspringen"
        case .hindi:        return "अभी के लिए छोड़ें"
        case .arabic:       return "تخطي الآن"
        case .russian:      return "Пропустить"
        case .polish:       return "Pomiń na teraz"
        }
    }

    // MARK: - News tab
    var loadingNewsLabel: String {
        switch self {
        case .english:      return "Loading trucking news..."
        case .portuguese:   return "Carregando notícias..."
        case .spanish:      return "Cargando noticias..."
        case .spanishLatam: return "Cargando noticias..."
        case .french:       return "Chargement des nouvelles..."
        case .german:       return "Nachrichten laden..."
        case .hindi:        return "समाचार लोड हो रहे हैं..."
        case .arabic:       return "جارٍ تحميل الأخبار..."
        case .russian:      return "Загрузка новостей..."
        case .polish:       return "Ładowanie wiadomości..."
        }
    }

    var truckingNewsTitle: String {
        switch self {
        case .english:      return "Trucking & Logistics News"
        case .portuguese:   return "Notícias de Transporte"
        case .spanish:      return "Noticias de Transporte"
        case .spanishLatam: return "Noticias de Transporte"
        case .french:       return "Actualités Transport"
        case .german:       return "Transport-Nachrichten"
        case .hindi:        return "ट्रकिंग समाचार"
        case .arabic:       return "أخبار النقل"
        case .russian:      return "Новости грузоперевозок"
        case .polish:       return "Wiadomości Transportowe"
        }
    }

    var addApiKeyLabel: String {
        switch self {
        case .english:      return "Add your NewsAPI key to load live news"
        case .portuguese:   return "Adicione sua chave NewsAPI para notícias ao vivo"
        case .spanish:      return "Agrega tu clave NewsAPI para noticias en vivo"
        case .spanishLatam: return "Agrega tu clave NewsAPI para noticias en vivo"
        case .french:       return "Ajoutez votre clé NewsAPI pour les actualités en direct"
        case .german:       return "NewsAPI-Schlüssel hinzufügen für Live-Nachrichten"
        case .hindi:        return "लाइव समाचार के लिए NewsAPI कुंजी जोड़ें"
        case .arabic:       return "أضف مفتاح NewsAPI لتحميل الأخبار الحية"
        case .russian:      return "Добавьте ключ NewsAPI для живых новостей"
        case .polish:       return "Dodaj klucz NewsAPI, aby ładować wiadomości na żywo"
        }
    }

    var tryAgainLabel: String {
        switch self {
        case .english:      return "Try Again"
        case .portuguese:   return "Tentar Novamente"
        case .spanish:      return "Intentar de Nuevo"
        case .spanishLatam: return "Intentar de Nuevo"
        case .french:       return "Réessayer"
        case .german:       return "Erneut versuchen"
        case .hindi:        return "पुनः प्रयास करें"
        case .arabic:       return "حاول مرة أخرى"
        case .russian:      return "Попробовать снова"
        case .polish:       return "Spróbuj ponownie"
        }
    }

    var okLabel: String {
        switch self {
        case .english:      return "OK"
        case .portuguese:   return "OK"
        case .spanish:      return "OK"
        case .spanishLatam: return "OK"
        case .french:       return "OK"
        case .german:       return "OK"
        case .hindi:        return "ठीक है"
        case .arabic:       return "حسناً"
        case .russian:      return "ОК"
        case .polish:       return "OK"
        }
    }

    // MARK: - Horizon / Map screen strings

    var truckRestrictionsOnRoute: String {
        switch self {
        case .english:      return "Truck Restrictions on Route"
        case .portuguese:   return "Restrições para Caminhões na Rota"
        case .spanish:      return "Restricciones para Camiones en Ruta"
        case .spanishLatam: return "Restricciones para Camiones en Ruta"
        case .french:       return "Restrictions Poids Lourds sur Route"
        case .german:       return "LKW-Beschränkungen auf der Route"
        case .hindi:        return "मार्ग पर ट्रक प्रतिबंध"
        case .arabic:       return "قيود الشاحنات على الطريق"
        case .russian:      return "Ограничения для грузовиков на маршруте"
        case .polish:       return "Ograniczenia dla Ciężarówek na Trasie"
        }
    }

    var searchingLabel: String {
        switch self {
        case .english:      return "Searching…"
        case .portuguese:   return "Buscando…"
        case .spanish:      return "Buscando…"
        case .spanishLatam: return "Buscando…"
        case .french:       return "Recherche…"
        case .german:       return "Suche…"
        case .hindi:        return "खोज रहे हैं…"
        case .arabic:       return "جاري البحث…"
        case .russian:      return "Поиск…"
        case .polish:       return "Szukam…"
        }
    }

    var itineraryLabel: String {
        switch self {
        case .english:      return "Itinerary"
        case .portuguese:   return "Itinerário"
        case .spanish:      return "Itinerario"
        case .spanishLatam: return "Itinerario"
        case .french:       return "Itinéraire"
        case .german:       return "Reiseroute"
        case .hindi:        return "यात्रा कार्यक्रम"
        case .arabic:       return "خط السير"
        case .russian:      return "Маршрут"
        case .polish:       return "Trasa"
        }
    }

    var clearTripLabel: String {
        switch self {
        case .english:      return "Clear Trip"
        case .portuguese:   return "Limpar Viagem"
        case .spanish:      return "Borrar Viaje"
        case .spanishLatam: return "Borrar Viaje"
        case .french:       return "Effacer Trajet"
        case .german:       return "Fahrt Löschen"
        case .hindi:        return "यात्रा साफ़ करें"
        case .arabic:       return "مسح الرحلة"
        case .russian:      return "Очистить маршрут"
        case .polish:       return "Usuń Trasę"
        }
    }

    var goLabel: String {
        switch self {
        case .english:      return "Go"
        case .portuguese:   return "Ir"
        case .spanish:      return "Ir"
        case .spanishLatam: return "Ir"
        case .french:       return "Aller"
        case .german:       return "Los"
        case .hindi:        return "जाएं"
        case .arabic:       return "انطلق"
        case .russian:      return "Ехать"
        case .polish:       return "Jedź"
        }
    }

    var shareTripProgressLabel: String {
        switch self {
        case .english:      return "Share Trip Progress"
        case .portuguese:   return "Compartilhar Progresso"
        case .spanish:      return "Compartir Progreso"
        case .spanishLatam: return "Compartir Progreso"
        case .french:       return "Partager la Progression"
        case .german:       return "Reisefortschritt Teilen"
        case .hindi:        return "यात्रा प्रगति साझा करें"
        case .arabic:       return "مشاركة تقدم الرحلة"
        case .russian:      return "Поделиться прогрессом"
        case .polish:       return "Udostępnij Postęp"
        }
    }

    var shareLocationWithDispatcher: String {
        switch self {
        case .english:      return "Share your real-time location and status with your Dispatcher"
        case .portuguese:   return "Compartilhe sua localização e status em tempo real com seu Despachante"
        case .spanish:      return "Comparte tu ubicación y estado en tiempo real con tu Despachador"
        case .spanishLatam: return "Comparte tu ubicación y estado en tiempo real con tu Despachador"
        case .french:       return "Partagez votre position et statut en temps réel avec votre Dispatcher"
        case .german:       return "Teilen Sie Ihren Echtzeit-Standort mit Ihrem Dispatcher"
        case .hindi:        return "अपना रीयल-टाइम स्थान और स्थिति अपने डिस्पैचर के साथ साझा करें"
        case .arabic:       return "شارك موقعك وحالتك في الوقت الفعلي مع المرسل"
        case .russian:      return "Поделитесь местоположением и статусом с диспетчером"
        case .polish:       return "Udostępnij lokalizację i status dyspozytorowi"
        }
    }

    var shareLabel: String {
        switch self {
        case .english:      return "Share"
        case .portuguese:   return "Compartilhar"
        case .spanish:      return "Compartir"
        case .spanishLatam: return "Compartir"
        case .french:       return "Partager"
        case .german:       return "Teilen"
        case .hindi:        return "साझा करें"
        case .arabic:       return "مشاركة"
        case .russian:      return "Поделиться"
        case .polish:       return "Udostępnij"
        }
    }

    var routeStepsLabel: String {
        switch self {
        case .english:      return "Route Steps"
        case .portuguese:   return "Etapas da Rota"
        case .spanish:      return "Pasos de Ruta"
        case .spanishLatam: return "Pasos de Ruta"
        case .french:       return "Étapes de l'Itinéraire"
        case .german:       return "Routenschritte"
        case .hindi:        return "मार्ग के चरण"
        case .arabic:       return "خطوات المسار"
        case .russian:      return "Шаги маршрута"
        case .polish:       return "Kroki Trasy"
        }
    }

    var noResultsNearby: String {
        switch self {
        case .english:      return "No results nearby"
        case .portuguese:   return "Nenhum resultado próximo"
        case .spanish:      return "Sin resultados cercanos"
        case .spanishLatam: return "Sin resultados cercanos"
        case .french:       return "Aucun résultat à proximité"
        case .german:       return "Keine Ergebnisse in der Nähe"
        case .hindi:        return "पास में कोई परिणाम नहीं"
        case .arabic:       return "لا توجد نتائج قريبة"
        case .russian:      return "Нет результатов поблизости"
        case .polish:       return "Brak wyników w pobliżu"
        }
    }

    var truckHeightLabel: String {
        switch self {
        case .english:      return "Height (m)"
        case .portuguese:   return "Altura (m)"
        case .spanish:      return "Altura (m)"
        case .spanishLatam: return "Altura (m)"
        case .french:       return "Hauteur (m)"
        case .german:       return "Höhe (m)"
        case .hindi:        return "ऊँचाई (मी)"
        case .arabic:       return "الارتفاع (م)"
        case .russian:      return "Высота (м)"
        case .polish:       return "Wysokość (m)"
        }
    }

    var truckWeightLabel: String {
        switch self {
        case .english:      return "Weight (tonnes)"
        case .portuguese:   return "Peso (toneladas)"
        case .spanish:      return "Peso (toneladas)"
        case .spanishLatam: return "Peso (toneladas)"
        case .french:       return "Poids (tonnes)"
        case .german:       return "Gewicht (Tonnen)"
        case .hindi:        return "वजन (टन)"
        case .arabic:       return "الوزن (طن)"
        case .russian:      return "Вес (тонн)"
        case .polish:       return "Masa (tony)"
        }
    }

    var truckLengthLabel: String {
        switch self {
        case .english:      return "Length (m)"
        case .portuguese:   return "Comprimento (m)"
        case .spanish:      return "Longitud (m)"
        case .spanishLatam: return "Longitud (m)"
        case .french:       return "Longueur (m)"
        case .german:       return "Länge (m)"
        case .hindi:        return "लंबाई (मी)"
        case .arabic:       return "الطول (م)"
        case .russian:      return "Длина (м)"
        case .polish:       return "Długość (m)"
        }
    }

    var newLoadAvailableLabel: String {
        switch self {
        case .english:      return "New Load Available"
        case .portuguese:   return "Nova Carga Disponível"
        case .spanish:      return "Nueva Carga Disponible"
        case .spanishLatam: return "Nueva Carga Disponible"
        case .french:       return "Nouvelle Charge Disponible"
        case .german:       return "Neue Ladung Verfügbar"
        case .hindi:        return "नया माल उपलब्ध है"
        case .arabic:       return "حمولة جديدة متاحة"
        case .russian:      return "Новый груз доступен"
        case .polish:       return "Nowy Ładunek Dostępny"
        }
    }

    var declineLabel: String {
        switch self {
        case .english:      return "Decline"
        case .portuguese:   return "Recusar"
        case .spanish:      return "Rechazar"
        case .spanishLatam: return "Rechazar"
        case .french:       return "Refuser"
        case .german:       return "Ablehnen"
        case .hindi:        return "अस्वीकार करें"
        case .arabic:       return "رفض"
        case .russian:      return "Отклонить"
        case .polish:       return "Odrzuć"
        }
    }

    var acceptAndNavigateLabel: String {
        switch self {
        case .english:      return "Accept & Navigate"
        case .portuguese:   return "Aceitar & Navegar"
        case .spanish:      return "Aceptar & Navegar"
        case .spanishLatam: return "Aceptar & Navegar"
        case .french:       return "Accepter & Naviguer"
        case .german:       return "Annehmen & Navigieren"
        case .hindi:        return "स्वीकार करें & नेविगेट करें"
        case .arabic:       return "قبول والتنقل"
        case .russian:      return "Принять и навигировать"
        case .polish:       return "Akceptuj & Nawiguj"
        }
    }

    var enterDestinationInstruction: String {
        switch self {
        case .english:      return "Enter the delivery destination to start navigation and log your trip."
        case .portuguese:   return "Insira o destino de entrega para iniciar a navegação e registrar sua viagem."
        case .spanish:      return "Ingresa el destino de entrega para iniciar la navegación y registrar tu viaje."
        case .spanishLatam: return "Ingresa el destino de entrega para iniciar la navegación y registrar tu viaje."
        case .french:       return "Entrez la destination de livraison pour démarrer la navigation et enregistrer votre trajet."
        case .german:       return "Geben Sie das Lieferziel ein, um die Navigation zu starten und Ihre Fahrt aufzuzeichnen."
        case .hindi:        return "नेविगेशन शुरू करने और अपनी यात्रा लॉग करने के लिए डिलीवरी गंतव्य दर्ज करें।"
        case .arabic:       return "أدخل وجهة التسليم لبدء الملاحة وتسجيل رحلتك."
        case .russian:      return "Введите пункт назначения для начала навигации и записи поездки."
        case .polish:       return "Podaj miejsce dostawy, aby rozpocząć nawigację i zalogować swoją trasę."
        }
    }

    var startTripLabel: String {
        switch self {
        case .english:      return "Start Trip"
        case .portuguese:   return "Iniciar Viagem"
        case .spanish:      return "Iniciar Viaje"
        case .spanishLatam: return "Iniciar Viaje"
        case .french:       return "Démarrer le Trajet"
        case .german:       return "Fahrt Starten"
        case .hindi:        return "यात्रा शुरू करें"
        case .arabic:       return "بدء الرحلة"
        case .russian:      return "Начать поездку"
        case .polish:       return "Rozpocznij Podróż"
        }
    }

    var wellnessCheckSubtitle: String {
        switch self {
        case .english:      return "A quick wellness check. Your safety matters."
        case .portuguese:   return "Uma verificação rápida de bem-estar. Sua segurança importa."
        case .spanish:      return "Una revisión rápida de bienestar. Tu seguridad importa."
        case .spanishLatam: return "Una revisión rápida de bienestar. Tu seguridad importa."
        case .french:       return "Un bilan de bien-être rapide. Votre sécurité compte."
        case .german:       return "Eine kurze Gesundheitsprüfung. Ihre Sicherheit ist wichtig."
        case .hindi:        return "एक त्वरित स्वास्थ्य जाँच। आपकी सुरक्षा महत्वपूर्ण है।"
        case .arabic:       return "فحص سريع للصحة. سلامتك تهمنا."
        case .russian:      return "Быстрая проверка самочувствия. Ваша безопасность важна."
        case .polish:       return "Szybkie sprawdzenie samopoczucia. Twoje bezpieczeństwo jest ważne."
        }
    }

    var skipLabel: String {
        switch self {
        case .english:      return "Skip"
        case .portuguese:   return "Pular"
        case .spanish:      return "Omitir"
        case .spanishLatam: return "Omitir"
        case .french:       return "Passer"
        case .german:       return "Überspringen"
        case .hindi:        return "छोड़ें"
        case .arabic:       return "تخطي"
        case .russian:      return "Пропустить"
        case .polish:       return "Pomiń"
        }
    }

    // MARK: - Voice Navigation strings

    var voiceAlertsLabel: String {
        switch self {
        case .english:      return "Voice Alerts"
        case .portuguese:   return "Alertas por Voz"
        case .spanish:      return "Alertas de Voz"
        case .spanishLatam: return "Alertas de Voz"
        case .french:       return "Alertes Vocales"
        case .german:       return "Sprachhinweise"
        case .hindi:        return "वॉइस अलर्ट"
        case .arabic:       return "تنبيهات صوتية"
        case .russian:      return "Голосовые оповещения"
        case .polish:       return "Alerty głosowe"
        }
    }

    var voiceNavOnLabel: String {
        switch self {
        case .english:      return "Voice navigation on"
        case .portuguese:   return "Navegação por voz ativada"
        case .spanish:      return "Navegación por voz activada"
        case .spanishLatam: return "Navegación por voz activada"
        case .french:       return "Navigation vocale activée"
        case .german:       return "Sprachnavigation eingeschaltet"
        case .hindi:        return "वॉइस नेविगेशन चालू"
        case .arabic:       return "الملاحة الصوتية مفعّلة"
        case .russian:      return "Голосовая навигация включена"
        case .polish:       return "Nawigacja głosowa włączona"
        }
    }

    var voiceNavOffLabel: String {
        switch self {
        case .english:      return "Voice navigation off"
        case .portuguese:   return "Navegação por voz desativada"
        case .spanish:      return "Navegación por voz desactivada"
        case .spanishLatam: return "Navegación por voz desactivada"
        case .french:       return "Navigation vocale désactivée"
        case .german:       return "Sprachnavigation ausgeschaltet"
        case .hindi:        return "वॉइस नेविगेशन बंद"
        case .arabic:       return "الملاحة الصوتية معطّلة"
        case .russian:      return "Голосовая навигация выключена"
        case .polish:       return "Nawigacja głosowa wyłączona"
        }
    }

    /// Spoken phrase: "In X, turn left/right onto Street Name"
    /// Use String.format: arg0 = distance, arg1 = instruction
    var voiceTurnPhrase: String {
        switch self {
        case .english:      return "In %@, %@"
        case .portuguese:   return "Em %@, %@"
        case .spanish:      return "En %@, %@"
        case .spanishLatam: return "En %@, %@"
        case .french:       return "Dans %@, %@"
        case .german:       return "In %@, %@"
        case .hindi:        return "%@ में, %@"
        case .arabic:       return "بعد %@، %@"
        case .russian:      return "Через %@, %@"
        case .polish:       return "Za %@, %@"
        }
    }

    /// Spoken phrase for arriving at destination
    var voiceArrivedPhrase: String {
        switch self {
        case .english:      return "You have arrived at your destination"
        case .portuguese:   return "Você chegou ao seu destino"
        case .spanish:      return "Has llegado a tu destino"
        case .spanishLatam: return "Has llegado a tu destino"
        case .french:       return "Vous êtes arrivé à destination"
        case .german:       return "Sie haben Ihr Ziel erreicht"
        case .hindi:        return "आप अपने गंतव्य पर पहुंच गए हैं"
        case .arabic:       return "لقد وصلت إلى وجهتك"
        case .russian:      return "Вы прибыли в место назначения"
        case .polish:       return "Dotarłeś do celu"
        }
    }

    /// Spoken phrase for scale/weigh station ahead
    var voiceScaleAheadPhrase: String {
        switch self {
        case .english:      return "Weigh station ahead in %@. Be prepared to stop."
        case .portuguese:   return "Balança a %@ à frente. Esteja preparado para parar."
        case .spanish:      return "Báscula a %@. Prepárate para detenerte."
        case .spanishLatam: return "Báscula a %@. Prepárate para detenerte."
        case .french:       return "Station de pesage dans %@. Préparez-vous à vous arrêter."
        case .german:       return "Waage in %@. Bereiten Sie sich auf einen Stopp vor."
        case .hindi:        return "%@ में तोल केंद्र। रुकने के लिए तैयार रहें।"
        case .arabic:       return "محطة الوزن على بُعد %@. كن مستعداً للتوقف."
        case .russian:      return "Весовая станция через %@. Приготовьтесь остановиться."
        case .polish:       return "Waga za %@. Przygotuj się na zatrzymanie."
        }
    }

    /// Voice: truck-stop diesel roughly half an hour ahead. Args: stop name, ETA minutes (rounded).
    var voiceTruckFuelEtaPhrase: String {
        switch self {
        case .english:      return "%@ — truck-stop diesel about %d minutes ahead."
        case .portuguese:   return "%@ — diesel para caminhões em cerca de %d minutos."
        case .spanish:      return "%@ — diésel para camiones en unos %d minutos."
        case .spanishLatam: return "%@ — diésel para camiones en unos %d minutos."
        case .french:       return "%@ — diesel poids lourd dans environ %d minutes."
        case .german:       return "%@ — LKW-Diesel in etwa %d Minuten."
        case .hindi:        return "%@ — लगभग %d मिनट में ट्रक डीज़ल।"
        case .arabic:       return "%@ — ديزل الشاحنات خلال نحو %d دقيقة."
        case .russian:      return "%@ — дизель для грузовиков примерно через %d минут."
        case .polish:       return "%@ — diesel dla ciężarówek za około %d minut."
        }
    }

    /// Optional suffix when weigh-station status is reported open (voice).
    var voiceScaleReportedOpenPhrase: String {
        switch self {
        case .english:      return "Drivers report the scale is open."
        case .portuguese:   return "Motoristas reportam balança aberta."
        case .spanish:      return "Otros conductores reportan báscula abierta."
        case .spanishLatam: return "Otros conductores reportan báscula abierta."
        case .french:       return "Signalement conducteurs : station ouverte."
        case .german:       return "Fahrer melden: Waage offen."
        case .hindi:        return "ड्राइवरों की रिपोर्ट: तौल खुला है।"
        case .arabic:       return "تقارير السائقين: المحطة مفتوحة."
        case .russian:      return "Водители сообщают: весовая открыта."
        case .polish:       return "Zgłoszenia kierowców: waga czynna."
        }
    }

    /// Optional suffix when weigh-station status is reported closed (voice).
    var voiceScaleReportedClosedPhrase: String {
        switch self {
        case .english:      return "Drivers report the scale is closed."
        case .portuguese:   return "Motoristas reportam balança fechada."
        case .spanish:      return "Otros conductores reportan báscula cerrada."
        case .spanishLatam: return "Otros conductores reportan báscula cerrada."
        case .french:       return "Signalement conducteurs : station fermée."
        case .german:       return "Fahrer melden: Waage geschlossen."
        case .hindi:        return "ड्राइवरों की रिपोर्ट: तौल बंद है।"
        case .arabic:       return "تقارير السائقين: المحطة مغلقة."
        case .russian:      return "Водители сообщают: весовая закрыта."
        case .polish:       return "Zgłoszenia kierowców: waga zamknięta."
        }
    }

    var voiceScaleOfficialOpenPhrase: String {
        switch self {
        case .english:      return "Official source reports the scale is open."
        case .portuguese:   return "Fonte oficial reporta balança aberta."
        case .spanish:      return "Fuente oficial reporta báscula abierta."
        case .spanishLatam: return "Fuente oficial reporta báscula abierta."
        case .french:       return "Source officielle : station ouverte."
        case .german:       return "Offizielle Quelle: Waage geöffnet."
        case .hindi:        return "आधिकारिक स्रोत: तौल खुला है।"
        case .arabic:       return "مصدر رسمي: المحطة مفتوحة."
        case .russian:      return "Официальный источник: весовая открыта."
        case .polish:       return "Źródło oficjalne: waga czynna."
        }
    }

    var voiceScaleOfficialClosedPhrase: String {
        switch self {
        case .english:      return "Official source reports the scale is closed."
        case .portuguese:   return "Fonte oficial reporta balança fechada."
        case .spanish:      return "Fuente oficial reporta báscula cerrada."
        case .spanishLatam: return "Fuente oficial reporta báscula cerrada."
        case .french:       return "Source officielle : station fermée."
        case .german:       return "Offizielle Quelle: Waage geschlossen."
        case .hindi:        return "आधिकारिक स्रोत: तौल बंद है।"
        case .arabic:       return "مصدر رسمي: المحطة مغلقة."
        case .russian:      return "Официальный источник: весовая закрыта."
        case .polish:       return "Źródło oficjalne: waga zamknięta."
        }
    }

    var voiceScaleUnconfirmedPhrase: String {
        switch self {
        case .english:      return "Status not officially confirmed. Be prepared to stop."
        case .portuguese:   return "Status não confirmado oficialmente. Prepare-se para parar."
        case .spanish:      return "Estado no confirmado oficialmente. Prepárate para detenerte."
        case .spanishLatam: return "Estado no confirmado oficialmente. Prepárate para detenerte."
        case .french:       return "Statut non confirmé officiellement. Préparez-vous à vous arrêter."
        case .german:       return "Status offiziell nicht bestätigt. Bereiten Sie einen Stopp vor."
        case .hindi:        return "स्थिति आधिकारिक रूप से अपुष्ट। रुकने की तैयारी करें।"
        case .arabic:       return "الحالة غير مؤكدة رسمياً. استعد للتوقف."
        case .russian:      return "Статус официально не подтверждён. Будьте готовы остановиться."
        case .polish:       return "Status niepotwierdzony oficjalnie. Przygotuj się do zatrzymania."
        }
    }

    /// Spoken phrase for police/accident alert
    var voiceRoadAlertPhrase: String {
        switch self {
        case .english:      return "%@ reported ahead. Drive carefully."
        case .portuguese:   return "%@ reportado à frente. Dirija com cuidado."
        case .spanish:      return "%@ reportado adelante. Conduce con cuidado."
        case .spanishLatam: return "%@ reportado adelante. Conduce con cuidado."
        case .french:       return "%@ signalé devant. Conduisez prudemment."
        case .german:       return "%@ voraus gemeldet. Bitte vorsichtig fahren."
        case .hindi:        return "आगे %@ की सूचना। सावधानी से चलाएं।"
        case .arabic:       return "تم الإبلاغ عن %@ أمامك. تحلَّ بالحذر."
        case .russian:      return "Впереди сообщают о %@. Езжайте осторожно."
        case .polish:       return "%@ zgłoszony z przodu. Jedź ostrożnie."
        }
    }

    /// Speech language BCP-47 code for AVSpeechSynthesisVoice
    var speechLanguageCode: String {
        switch self {
        case .english:      return "en-US"
        case .portuguese:   return "pt-BR"
        case .spanish:      return "es-ES"
        case .spanishLatam: return "es-MX"
        case .french:       return "fr-FR"
        case .german:       return "de-DE"
        case .hindi:        return "hi-IN"
        case .arabic:       return "ar-SA"
        case .russian:      return "ru-RU"
        case .polish:       return "pl-PL"
        }
    }

    // MARK: - Horizon alerts, routing errors, geofence (UI)

    var horizonRouteErrorTitle: String {
        switch self {
        case .english, .hindi, .arabic: return "Route Error"
        case .portuguese: return "Erro de rota"
        case .spanish, .spanishLatam: return "Error de ruta"
        case .french: return "Erreur d’itinéraire"
        case .german: return "Routenfehler"
        case .polish: return "Błąd trasy"
        case .russian: return "Ошибка маршрута"
        }
    }

    var horizonRoutingNoticeTitle: String {
        switch self {
        case .english, .hindi, .arabic: return "Routing Notice"
        case .portuguese: return "Aviso de roteamento"
        case .spanish, .spanishLatam: return "Aviso de ruta"
        case .french: return "Avis d’itinéraire"
        case .german: return "Routing-Hinweis"
        case .polish: return "Powiadomienie o trasie"
        case .russian: return "Уведомление о маршруте"
        }
    }

    var horizonRouteErrorCouldNotCalculate: String {
        switch self {
        case .english, .hindi, .arabic: return "Could not calculate route"
        case .portuguese: return "Não foi possível calcular a rota"
        case .spanish, .spanishLatam: return "No se pudo calcular la ruta"
        case .french: return "Impossible de calculer l’itinéraire"
        case .german: return "Route konnte nicht berechnet werden"
        case .polish: return "Nie udało się obliczyć trasy"
        case .russian: return "Не удалось построить маршрут"
        }
    }

    var horizonRouteErrorLocationUnavailable: String {
        switch self {
        case .english, .hindi, .arabic: return "Location unavailable. Check GPS."
        case .portuguese: return "Localização indisponível. Verifique o GPS."
        case .spanish, .spanishLatam: return "Ubicación no disponible. Compruebe el GPS."
        case .french: return "Position indisponible. Vérifiez le GPS."
        case .german: return "Standort nicht verfügbar. GPS prüfen."
        case .polish: return "Lokalizacja niedostępna. Sprawdź GPS."
        case .russian: return "Местоположение недоступно. Проверьте GPS."
        }
    }

    var horizonRouteErrorValhallaUnavailable: String {
        switch self {
        case .english, .hindi, .arabic:
            return "Truck routing server (Valhalla) is unavailable. Check your connection and try again. Car routes are not used."
        case .portuguese:
            return "Servidor de rotas para caminhão (Valhalla) indisponível. Verifique a conexão e tente de novo. Rotas de carro não são usadas."
        case .spanish, .spanishLatam:
            return "Servidor de rutas para camión (Valhalla) no disponible. Compruebe la conexión. No se usan rutas de coche."
        case .french:
            return "Serveur Valhalla (poids lourds) indisponible. Vérifiez la connexion. Pas d’itinéraires voiture."
        case .german:
            return "Valhalla-LKW-Routing nicht erreichbar. Verbindung prüfen. Keine Pkw-Routen."
        case .polish:
            return "Serwer Valhalla (ciężarówka) niedostępny. Sprawdź połączenie. Bez tras samochodowych."
        case .russian:
            return "Сервер Valhalla (грузовик) недоступен. Проверьте связь. Маршруты легковых авто не используются."
        }
    }

    var horizonRerouteFailedMessage: String {
        switch self {
        case .english, .hindi, .arabic:
            return "Could not recalculate route — continuing on current path. Check signal or truck routing server."
        case .portuguese:
            return "Não foi possível recalcular a rota — continuando no trajeto atual. Verifique sinal ou servidor Valhalla."
        case .spanish, .spanishLatam:
            return "No se pudo recalcular la ruta — sigue la ruta actual. Compruebe señal o servidor Valhalla."
        case .french:
            return "Impossible de recalculer — poursuite sur l’itinéraire actuel. Vérifiez le signal ou Valhalla."
        case .german:
            return "Neuberechnung fehlgeschlagen — aktuelle Route beibehalten. Signal oder Valhalla prüfen."
        case .polish:
            return "Nie udało się przeliczyć trasy — kontynuuj obecną. Sprawdź zasięg lub Valhalla."
        case .russian:
            return "Не удалось перестроить маршрут — продолжайте по текущему. Проверьте связь или Valhalla."
        }
    }

    var horizonRouteErrorUnableSafeRoute: String {
        switch self {
        case .english, .hindi, .arabic: return "Unable to calculate a safe route right now. Check signal and try again."
        case .portuguese: return "Não foi possível calcular uma rota segura agora. Verifique o sinal e tente de novo."
        case .spanish, .spanishLatam: return "No se puede calcular una ruta segura ahora. Compruebe la señal e inténtelo de nuevo."
        case .french: return "Impossible de calculer un itinéraire sûr pour le moment. Vérifiez le signal et réessayez."
        case .german: return "Jetzt keine sichere Route berechenbar. Signal prüfen und erneut versuchen."
        case .polish: return "Teraz nie można obliczyć bezpiecznej trasy. Sprawdź zasięg i spróbuj ponownie."
        case .russian: return "Сейчас не удаётся построить безопасный маршрут. Проверьте связь и повторите."
        }
    }

    var horizonRouteErrorAddressNoSafeRoute: String {
        switch self {
        case .english, .hindi, .arabic: return "Address resolved to coordinates, but safe route is unavailable. Try again."
        case .portuguese: return "Endereço convertido em coordenadas, mas rota segura indisponível. Tente de novo."
        case .spanish, .spanishLatam: return "Dirección resuelta a coordenadas, pero la ruta segura no está disponible. Inténtelo de nuevo."
        case .french: return "Adresse géolocalisée, mais itinéraire sûr indisponible. Réessayez."
        case .german: return "Adresse auf Koordinaten gelöst, aber keine sichere Route. Erneut versuchen."
        case .polish: return "Adres współrzędnych, ale bezpieczna trasa niedostępna. Spróbuj ponownie."
        case .russian: return "Адрес найден по координатам, но безопасный маршрут недоступен. Повторите."
        }
    }

    var horizonRouteErrorCouldNotResolveAddress: String {
        switch self {
        case .english, .hindi, .arabic: return "Could not resolve destination address. Please pick a destination from Search."
        case .portuguese: return "Não foi possível resolver o endereço de destino. Escolha um destino na Busca."
        case .spanish, .spanishLatam: return "No se pudo resolver la dirección de destino. Elija un destino en Búsqueda."
        case .french: return "Impossible de résoudre l’adresse de destination. Choisissez une destination dans Recherche."
        case .german: return "Zieladresse nicht auflösbar. Bitte Ziel in der Suche wählen."
        case .polish: return "Nie można znaleźć adresu celu. Wybierz cel z wyszukiwania."
        case .russian: return "Не удалось определить адрес назначения. Выберите пункт в поиске."
        }
    }

    var horizonRouteErrorNoCoordinates: String {
        switch self {
        case .english, .hindi, .arabic: return "Route has no coordinates"
        case .portuguese: return "A rota não tem coordenadas"
        case .spanish, .spanishLatam: return "La ruta no tiene coordenadas"
        case .french: return "L’itinéraire n’a pas de coordonnées"
        case .german: return "Route ohne Koordinaten"
        case .polish: return "Trasa bez współrzędnych"
        case .russian: return "У маршрута нет координат"
        }
    }

    var horizonRouteErrorZeroDistance: String {
        switch self {
        case .english, .hindi, .arabic: return "Route distance is zero"
        case .portuguese: return "Distância da rota é zero"
        case .spanish, .spanishLatam: return "La distancia de la ruta es cero"
        case .french: return "Distance d’itinéraire nulle"
        case .german: return "Routenentfernung ist null"
        case .polish: return "Dystans trasy wynosi zero"
        case .russian: return "Длина маршрута равна нулю"
        }
    }

    var horizonRoutingNoticeDefault: String {
        switch self {
        case .english, .hindi, .arabic: return "Route provider changed."
        case .portuguese: return "O provedor de rota mudou."
        case .spanish, .spanishLatam: return "El proveedor de ruta cambió."
        case .french: return "Le fournisseur d’itinéraire a changé."
        case .german: return "Routenanbieter gewechselt."
        case .polish: return "Zmieniono dostawcę trasy."
        case .russian: return "Сменился поставщик маршрута."
        }
    }

    func horizonRoutingNoticeSimple(provider: String) -> String {
        switch self {
        case .english, .hindi, .arabic: return "Route via \(provider) — truck restrictions may be limited."
        case .portuguese: return "Rota via \(provider) — restrições de caminhão podem ser limitadas."
        case .spanish, .spanishLatam: return "Ruta vía \(provider) — las restricciones para camiones pueden ser limitadas."
        case .french: return "Itinéraire via \(provider) — restrictions poids lourds possibles."
        case .german: return "Route über \(provider) — LKW-Beschränkungen können begrenzt sein."
        case .polish: return "Trasa przez \(provider) — ograniczenia dla ciężarówek mogą być ograniczone."
        case .russian: return "Маршрут через \(provider) — ограничения для грузовиков могут быть ограничены."
        }
    }

    func horizonRoutingNoticeQuantum(provider: String, solver: String) -> String {
        switch self {
        case .english, .hindi, .arabic:
            return "Road line uses \(provider). Stop order came from Trucker Easy optimize (\(solver)). Truck dimensions on this segment may be limited."
        case .portuguese:
            return "A linha da estrada usa \(provider). A ordem das paradas veio do optimize Trucker Easy (\(solver)). Dimensões do caminhão neste trecho podem ser limitadas."
        case .spanish, .spanishLatam:
            return "La línea de ruta usa \(provider). El orden de paradas proviene del optimize de Trucker Easy (\(solver)). Las dimensiones del camión en este tramo pueden ser limitadas."
        case .french:
            return "La ligne suit \(provider). L’ordre des arrêts vient de l’optimisation Trucker Easy (\(solver)). Gabarit poids lourds possiblement limité sur ce segment."
        case .german:
            return "Streckenlinie über \(provider). Stoppreihenfolge von Trucker Easy Optimize (\(solver)). LKW-Maße auf diesem Abschnitt ggf. begrenzt."
        case .polish:
            return "Linia trasy: \(provider). Kolejność przystanków z optymalizacji Trucker Easy (\(solver)). Wymiary pojazdu na tym odcinku mogą być ograniczone."
        case .russian:
            return "Линия маршрута: \(provider). Порядок остановок из оптимизации Trucker Easy (\(solver)). Габариты на участке могут быть ограничены."
        }
    }

    var routeEasyPickerTitle: String {
        switch self {
        case .english, .hindi, .arabic: return "Choose your route"
        case .portuguese: return "Escolha sua rota"
        case .spanish, .spanishLatam: return "Elige tu ruta"
        case .french: return "Choisissez votre itinéraire"
        case .german: return "Route wählen"
        case .polish: return "Wybierz trasę"
        case .russian: return "Выберите маршрут"
        }
    }

    var routeEasyPickerSubtitle: String {
        switch self {
        case .english, .hindi, .arabic:
            return "Compare free, no-toll, and AI-optimized routes. Upgrade to unlock truck-safe savings."
        case .portuguese:
            return "Compare rota grátis, sem pedágio e rota inteligente. Faça upgrade para economia com caminhão."
        case .spanish, .spanishLatam:
            return "Compara ruta gratis, sin peajes e inteligente. Mejora el plan para ahorrar con camión."
        case .french:
            return "Comparez gratuit, sans péage et IA. Passez au plan supérieur pour économiser."
        case .german:
            return "Vergleiche Free, mautfrei und KI-Route. Upgrade für LKW-Einsparungen."
        case .polish:
            return "Porównaj darmową, bez opłat i AI. Ulepsz plan dla oszczędności ciężarówki."
        case .russian:
            return "Сравните бесплатный, без платных дорог и ИИ-маршрут. Обновите план для экономии."
        }
    }

    var routeEasyPlanFree: String {
        switch self {
        case .portuguese: return "Grátis"
        case .spanish, .spanishLatam: return "Gratis"
        case .french: return "Gratuit"
        case .german: return "Free"
        case .polish: return "Free"
        case .russian: return "Free"
        default: return "Free"
        }
    }

    var routeEasyKindFastest: String {
        switch self {
        case .portuguese: return "Rota rápida"
        case .spanish, .spanishLatam: return "Ruta rápida"
        default: return "Fastest"
        }
    }

    var routeEasyKindNoTolls: String {
        switch self {
        case .portuguese: return "Sem pedágio"
        case .spanish, .spanishLatam: return "Sin peajes"
        default: return "No tolls"
        }
    }

    var routeEasyKindSmart: String {
        switch self {
        case .portuguese: return "Rota inteligente"
        case .spanish, .spanishLatam: return "Ruta inteligente"
        default: return "AI Smart"
        }
    }

    var routeEasyPickerTestingSubtitle: String {
        switch self {
        case .portuguese:
            return "Build de teste — escolha Rápida, Sem pedágio ou Inteligente. Todas funcionam."
        case .spanish, .spanishLatam:
            return "Build de prueba — elige Rápida, Sin peajes o Inteligente. Todas funcionan."
        default:
            return "Test build — pick Fastest, No toll, or AI Smart. All three work."
        }
    }

    var routeEasyTestingBanner: String {
        switch self {
        case .portuguese: return "Modo teste: sem checkout — toque numa rota para navegar."
        case .spanish, .spanishLatam: return "Modo prueba: sin pago — toca una ruta para navegar."
        default: return "Test mode: no checkout — tap any route to start navigation."
        }
    }

    var routeEasyComparePlans: String {
        switch self {
        case .portuguese: return "Ver planos e preços"
        case .spanish, .spanishLatam: return "Ver planes y precios"
        default: return "See plans & pricing"
        }
    }

    var routeEasyStartNavigation: String {
        switch self {
        case .portuguese: return "Iniciar navegação"
        case .spanish, .spanishLatam: return "Iniciar navegación"
        default: return "Start navigation"
        }
    }

    func routeEasyUnlockPlan(_ planName: String) -> String {
        switch self {
        case .portuguese: return "Desbloquear com \(planName)"
        case .spanish, .spanishLatam: return "Desbloquear con \(planName)"
        default: return "Unlock with \(planName)"
        }
    }

    func routeEasyEstimatedSavings(_ usd: Double) -> String {
        switch self {
        case .portuguese: return "Economia estimada ~$\(String(format: "%.0f", usd))"
        case .spanish, .spanishLatam: return "Ahorro estimado ~$\(String(format: "%.0f", usd))"
        default: return "Est. savings ~$\(String(format: "%.0f", usd))"
        }
    }

    var horizonTruckSafeUnavailableTitle: String {
        switch self {
        case .english, .hindi, .arabic: return "Truck-safe route unavailable"
        case .portuguese: return "Rota segura para caminhão indisponível"
        case .spanish, .spanishLatam: return "Ruta segura para camión no disponible"
        case .french: return "Itinéraire poids lourds indisponible"
        case .german: return "LKW-sichere Route nicht verfügbar"
        case .polish: return "Bezpieczna trasa dla ciężarówki niedostępna"
        case .russian: return "Безопасный маршрут для грузовика недоступен"
        }
    }

    func horizonTruckSafeFallbackExplanation(provider: String) -> String {
        switch self {
        case .english, .hindi, .arabic:
            return "No truck-safe provider responded. Continue with \(provider) for basic navigation while restrictions may be limited."
        case .portuguese:
            return "Nenhum provedor seguro para caminhão respondeu. Continuar com \(provider) para navegação básica; restrições podem ser limitadas."
        case .spanish, .spanishLatam:
            return "Ningún proveedor seguro para camión respondió. Continuar con \(provider) para navegación básica; las restricciones pueden ser limitadas."
        case .french:
            return "Aucun fournisseur poids lourds n’a répondu. Continuer avec \(provider) pour une navigation basique ; restrictions possibles."
        case .german:
            return "Kein LKW-sicherer Anbieter antwortet. Mit \(provider) für Basisnavigation fortfahren; Beschränkungen möglich."
        case .polish:
            return "Brak odpowiedzi od dostawcy bezpiecznego dla ciężarówki. Kontynuuj z \(provider) — ograniczenia mogą obowiązywać."
        case .russian:
            return "Нет ответа от поставщика с учётом грузовика. Продолжить с \(provider) — ограничения могут действовать."
        }
    }

    var truckSafeOnlyToggleTitle: String {
        switch self {
        case .english, .hindi, .arabic: return "Truck-safe routes only"
        case .portuguese: return "Apenas rotas seguras para caminhão"
        case .spanish, .spanishLatam: return "Solo rutas seguras para camión"
        case .french: return "Itinéraires poids lourds uniquement"
        case .german: return "Nur LKW-sichere Routen"
        case .polish: return "Tylko trasy bezpieczne dla ciężarówki"
        case .russian: return "Только маршруты для грузовиков"
        }
    }

    var truckSafeOnlyToggleFooter: String {
        switch self {
        case .english, .hindi, .arabic:
            return "Uses Valhalla truck costing only. If Valhalla is offline, the app shows an error instead of OSRM or Apple Maps (car-grade routes)."
        case .portuguese:
            return "Usa só Valhalla (costing caminhão). Se o Valhalla estiver offline, o app mostra erro em vez de OSRM ou MapKit (rotas de carro)."
        case .spanish, .spanishLatam:
            return "Solo Valhalla (camión). Si Valhalla no responde, el app muestra error en lugar de OSRM o MapKit (rutas de coche)."
        case .french:
            return "Valhalla poids lourds uniquement. Si Valhalla est hors ligne, erreur au lieu d’OSRM ou MapKit (itinéraires voiture)."
        case .german:
            return "Nur Valhalla (LKW). Wenn Valhalla offline ist, Fehler statt OSRM/MapKit (Pkw-Routen)."
        case .polish:
            return "Tylko Valhalla (ciężarówka). Gdy Valhalla offline — błąd zamiast OSRM/MapKit (trasy samochodowe)."
        case .russian:
            return "Только Valhalla (грузовик). Если Valhalla недоступен — ошибка вместо OSRM/MapKit (легковые маршруты)."
        }
    }

    var horizonContinueWithFallbackGPS: String {
        switch self {
        case .english, .hindi, .arabic: return "Continue with fallback GPS"
        case .portuguese: return "Continuar com GPS alternativo"
        case .spanish, .spanishLatam: return "Continuar con GPS alternativo"
        case .french: return "Continuer avec le GPS de secours"
        case .german: return "Mit Fallback-GPS fortfahren"
        case .polish: return "Kontynuuj z zapasowym GPS"
        case .russian: return "Продолжить с запасным GPS"
        }
    }

    var horizonYouHaveArrived: String {
        switch self {
        case .english, .hindi, .arabic: return "You have arrived!"
        case .portuguese: return "Você chegou!"
        case .spanish, .spanishLatam: return "¡Has llegado!"
        case .french: return "Vous êtes arrivé !"
        case .german: return "Sie sind angekommen!"
        case .polish: return "Jesteś na miejscu!"
        case .russian: return "Вы прибыли!"
        }
    }

    func horizonGpsLive(accuracyMeters: Int) -> String {
        switch self {
        case .english, .hindi, .arabic: return "GPS live · ±\(accuracyMeters)m"
        case .portuguese: return "GPS ao vivo · ±\(accuracyMeters)m"
        case .spanish, .spanishLatam: return "GPS en vivo · ±\(accuracyMeters)m"
        case .french: return "GPS actif · ±\(accuracyMeters)m"
        case .german: return "GPS live · ±\(accuracyMeters)m"
        case .polish: return "GPS na żywo · ±\(accuracyMeters)m"
        case .russian: return "GPS онлайн · ±\(accuracyMeters)м"
        }
    }

    func horizonGpsStale(seconds: Int) -> String {
        switch self {
        case .english, .hindi, .arabic: return "GPS stale · \(seconds)s"
        case .portuguese: return "GPS desatualizado · \(seconds)s"
        case .spanish, .spanishLatam: return "GPS desactualizado · \(seconds)s"
        case .french: return "GPS obsolète · \(seconds)s"
        case .german: return "GPS veraltet · \(seconds)s"
        case .polish: return "GPS nieaktualne · \(seconds)s"
        case .russian: return "GPS устарел · \(seconds)с"
        }
    }

    var horizonGpsSearching: String {
        switch self {
        case .english, .hindi, .arabic: return "GPS searching"
        case .portuguese: return "Buscando GPS"
        case .spanish, .spanishLatam: return "Buscando GPS"
        case .french: return "Recherche GPS"
        case .german: return "GPS wird gesucht"
        case .polish: return "Szukanie GPS"
        case .russian: return "Поиск GPS"
        }
    }

    var horizonNearbyWeighStationDefault: String {
        switch self {
        case .english, .hindi, .arabic: return "Nearby Weigh Station"
        case .portuguese: return "Balança próxima"
        case .spanish, .spanishLatam: return "Báscula cercana"
        case .french: return "Station de pesage proche"
        case .german: return "Waage in der Nähe"
        case .polish: return "Waga w pobliżu"
        case .russian: return "Весовая поблизости"
        }
    }

    var horizonGenericWeighStation: String {
        switch self {
        case .english, .hindi, .arabic: return "Weigh Station"
        case .portuguese: return "Balança"
        case .spanish, .spanishLatam: return "Báscula"
        case .french: return "Station de pesage"
        case .german: return "Waage"
        case .polish: return "Waga"
        case .russian: return "Весовая"
        }
    }

    var horizonArrivalYourDestination: String {
        switch self {
        case .english, .hindi, .arabic: return "your destination"
        case .portuguese: return "seu destino"
        case .spanish, .spanishLatam: return "tu destino"
        case .french: return "votre destination"
        case .german: return "Ihr Ziel"
        case .polish: return "cel podróży"
        case .russian: return "ваш пункт назначения"
        }
    }

    var horizonEmergencyRouteDetails: String {
        switch self {
        case .english, .hindi, .arabic:
            return "Road graph unavailable; using direct guidance line."
        case .portuguese:
            return "Mapa de estradas indisponível; usando linha de orientação direta."
        case .spanish, .spanishLatam:
            return "Grafo de carreteras no disponible; usando línea de guía directa."
        case .french:
            return "Réseau routier indisponible ; ligne de guidage directe."
        case .german:
            return "Straßengraph nicht verfügbar; direkte Führungslinie."
        case .polish:
            return "Sieć dróg niedostępna; użyto prostej linii prowadzenia."
        case .russian:
            return "Дорожный граф недоступен; используется прямая линия навигации."
        }
    }

    var horizonIdleQuickPlaces: String {
        switch self {
        case .english, .hindi, .arabic: return "Places"
        case .portuguese: return "Lugares"
        case .spanish, .spanishLatam: return "Lugares"
        case .french: return "Lieux"
        case .german: return "Orte"
        case .polish: return "Miejsca"
        case .russian: return "Места"
        }
    }

    var horizonIdleQuickFuel: String {
        switch self {
        case .english, .hindi, .arabic: return "Fuel"
        case .portuguese: return "Combustível"
        case .spanish, .spanishLatam: return "Combustible"
        case .french: return "Carburant"
        case .german: return "Tanken"
        case .polish: return "Paliwo"
        case .russian: return "Топливо"
        }
    }

    var horizonIdleQuickWeigh: String {
        switch self {
        case .english, .hindi, .arabic: return "DOT / Weigh"
        case .portuguese: return "DOT / Balança"
        case .spanish, .spanishLatam: return "DOT / Báscula"
        case .french: return "DOT / Pesage"
        case .german: return "DOT / Waage"
        case .polish: return "DOT / Waga"
        case .russian: return "DOT / Взвешивание"
        }
    }

    var horizonIdleQuickRest: String {
        switch self {
        case .english, .hindi, .arabic: return "Rest"
        case .portuguese: return "Descanso"
        case .spanish, .spanishLatam: return "Descanso"
        case .french: return "Repos"
        case .german: return "Pause"
        case .polish: return "Odpoczynek"
        case .russian: return "Отдых"
        }
    }

    var horizonHOSDetail: String {
        switch self {
        case .english, .hindi, .arabic: return "HOS detail"
        case .portuguese: return "Detalhe Jornada"
        case .spanish, .spanishLatam: return "Detalle HOS"
        case .french: return "Détail HOS"
        case .german: return "HOS-Details"
        case .polish: return "Szczegóły HOS"
        case .russian: return "Детали HOS"
        }
    }

    var horizonHOSSettings: String {
        switch self {
        case .english, .hindi, .arabic: return "HOS settings"
        case .portuguese: return "Config. Jornada"
        case .spanish, .spanishLatam: return "Ajustes HOS"
        case .french: return "Réglages HOS"
        case .german: return "HOS-Einstellungen"
        case .polish: return "Ustawienia HOS"
        case .russian: return "Настройки HOS"
        }
    }

    func horizonGeofenceBanner(isEntry: Bool, name: String) -> String {
        let title: String
        switch self {
        case .english, .hindi, .arabic:
            title = isEntry ? "Entered geofence" : "Exited geofence"
        case .portuguese:
            title = isEntry ? "Entrou na cerca geográfica" : "Saiu da cerca geográfica"
        case .spanish, .spanishLatam:
            title = isEntry ? "Entró en la geovalla" : "Salió de la geovalla"
        case .french:
            title = isEntry ? "Entrée dans la géorepère" : "Sortie de la géorepère"
        case .german:
            title = isEntry ? "Geofence betreten" : "Geofence verlassen"
        case .polish:
            title = isEntry ? "Wejście do geofence" : "Wyjście z geofence"
        case .russian:
            title = isEntry ? "Вход в геозону" : "Выход из геозоны"
        }
        return "\(title): \(name)"
    }

    func horizonNavigateToDestination(_ name: String) -> String {
        switch self {
        case .english, .hindi, .arabic: return "Navigate to \(name)"
        case .portuguese: return "Navegar até \(name)"
        case .spanish, .spanishLatam: return "Navegar a \(name)"
        case .french: return "Naviguer vers \(name)"
        case .german: return "Nach \(name) navigieren"
        case .polish: return "Nawiguj do \(name)"
        case .russian: return "Навигация до \(name)"
        }
    }

    var horizonEmergencyRouteTitle: String {
        switch self {
        case .english, .hindi, .arabic: return "Emergency route mode"
        case .portuguese: return "Modo rota de emergência"
        case .spanish, .spanishLatam: return "Modo ruta de emergencia"
        case .french: return "Mode itinéraire d’urgence"
        case .german: return "Notroutenmodus"
        case .polish: return "Tryb trasy awaryjnej"
        case .russian: return "Аварийный режим маршрута"
        }
    }
}

// MARK: - Supported Regions (expanded globally)
enum SupportedRegion: String, CaseIterable, Identifiable {
    case usa       = "USA"
    case canada    = "Canada"
    case mexico    = "Mexico"
    case brazil    = "Brazil"
    case europe    = "Europe (EU)"
    case uk        = "United Kingdom"
    case australia = "Australia"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .usa:       return Locale(identifier: "en_US")
        case .canada:    return Locale(identifier: "en_CA")
        case .mexico:    return Locale(identifier: "es_MX")
        case .brazil:    return Locale(identifier: "pt_BR")
        case .europe:    return Locale(identifier: "en_GB")
        case .uk:        return Locale(identifier: "en_GB")
        case .australia: return Locale(identifier: "en_AU")
        }
    }

    var defaultLanguage: AppLanguage {
        switch self {
        case .usa, .canada, .uk, .australia: return .english
        case .mexico:    return .spanishLatam
        case .brazil:    return .portuguese
        case .europe:    return .english
        }
    }

    var currency: String {
        switch self {
        case .usa:       return "USD"
        case .canada:    return "CAD"
        case .mexico:    return "MXN"
        case .brazil:    return "BRL"
        case .europe:    return "EUR"
        case .uk:        return "GBP"
        case .australia: return "AUD"
        }
    }

    var currencySymbol: String {
        switch self {
        case .usa:       return "$"
        case .canada:    return "C$"
        case .mexico:    return "MX$"
        case .brazil:    return "R$"
        case .europe:    return "€"
        case .uk:        return "£"
        case .australia: return "A$"
        }
    }

    var distanceUnit: String {
        switch self {
        case .usa, .canada, .mexico: return "mi"
        case .brazil, .europe, .uk, .australia: return "km"
        }
    }

    var usesMetric: Bool {
        distanceUnit == "km"
    }

    var fuelUnit: String {
        switch self {
        case .usa: return "gal"
        case .canada, .mexico, .brazil, .europe, .uk, .australia: return "L"
        }
    }

    var temperatureUnit: String {
        switch self {
        case .usa: return "°F"
        case .canada, .mexico, .brazil, .europe, .uk, .australia: return "°C"
        }
    }

    var weightUnit: String {
        switch self {
        case .usa, .canada: return "lbs"
        case .mexico, .brazil, .europe, .uk, .australia: return "tonnes"
        }
    }

    var speedUnit: String {
        switch self {
        case .usa, .canada, .mexico: return "mph"
        case .brazil, .europe, .uk, .australia: return "km/h"
        }
    }

    var dateFormat: String {
        switch self {
        case .usa:               return "MM/dd/yyyy"
        case .canada:            return "yyyy-MM-dd"
        case .europe, .uk:       return "dd/MM/yyyy"
        case .mexico, .brazil:   return "dd/MM/yyyy"
        case .australia:         return "dd/MM/yyyy"
        }
    }

    // HOS rules for this region
    var hosRules: HOSRules {
        switch self {
        case .usa:       return HOSRules.usa
        case .canada:    return HOSRules.canada
        case .mexico:    return HOSRules.mexico
        case .brazil:    return HOSRules.brazil
        case .europe:    return HOSRules.europe
        case .uk:        return HOSRules.uk
        case .australia: return HOSRules.australia
        }
    }

    var states: [String] {
        switch self {
        case .usa:
            return ["AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA",
                    "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
                    "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
                    "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC",
                    "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY"]
        case .canada:
            return ["AB","BC","MB","NB","NL","NS","NT","NU","ON","PE","QC","SK","YT"]
        case .mexico:
            return ["AGS","BC","BCS","CAMP","CHIS","CHIH","COAH","COL","CDMX","DGO",
                    "GTO","GRO","HGO","JAL","MEX","MICH","MOR","NAY","NL","OAX",
                    "PUE","QRO","QROO","SLP","SIN","SON","TAB","TAMPS","TLAX","VER","YUC","ZAC"]
        case .brazil:
            return ["AC","AL","AP","AM","BA","CE","DF","ES","GO","MA",
                    "MT","MS","MG","PA","PB","PR","PE","PI","RJ","RN",
                    "RS","RO","RR","SC","SP","SE","TO"]
        case .europe:
            return ["AT","BE","BG","HR","CY","CZ","DK","EE","FI","FR",
                    "DE","GR","HU","IE","IT","LV","LT","LU","MT","NL",
                    "PL","PT","RO","SK","SI","ES","SE"]
        case .uk:
            return ["England","Scotland","Wales","Northern Ireland"]
        case .australia:
            return ["NSW","VIC","QLD","SA","WA","TAS","ACT","NT"]
        }
    }

    var stateLabel: String {
        switch self {
        case .usa:       return "State"
        case .canada:    return "Province"
        case .mexico:    return "Estado"
        case .brazil:    return "Estado"
        case .europe:    return "Country"
        case .uk:        return "Region"
        case .australia: return "State/Territory"
        }
    }

    var flagEmoji: String {
        switch self {
        case .usa:       return "🇺🇸"
        case .canada:    return "🇨🇦"
        case .mexico:    return "🇲🇽"
        case .brazil:    return "🇧🇷"
        case .europe:    return "🇪🇺"
        case .uk:        return "🇬🇧"
        case .australia: return "🇦🇺"
        }
    }

    // MARK: - Distance formatting
    func formatDistance(_ meters: Double) -> String {
        if usesMetric {
            let km = meters / 1000.0
            if km < 1 {
                return String(format: "%.0f m", meters)
            }
            return String(format: "%.1f km", km)
        } else {
            let miles = meters / 1609.34
            if miles < 0.1 {
                let feet = meters * 3.28084
                return String(format: "%.0f ft", feet)
            }
            return String(format: "%.1f mi", miles)
        }
    }

    func formatWeight(_ kg: Double) -> String {
        if weightUnit == "lbs" {
            return String(format: "%.0f lbs", kg * 2.20462)
        } else {
            return String(format: "%.1f t", kg / 1000.0)
        }
    }

    func formatSpeed(_ kmh: Double) -> String {
        if speedUnit == "mph" {
            return String(format: "%.0f mph", kmh / 1.60934)
        } else {
            return String(format: "%.0f km/h", kmh)
        }
    }

    func convertDistance(_ meters: Double) -> Double {
        if usesMetric {
            return meters / 1000.0
        } else {
            return meters / 1609.34
        }
    }

    func convertFuel(_ fuel: Double, to targetRegion: SupportedRegion) -> Double {
        let liters: Double = (self.fuelUnit == "gal") ? fuel * 3.78541 : fuel
        return (targetRegion.fuelUnit == "gal") ? liters / 3.78541 : liters
    }
}

extension AppLanguage {
    /// Valhalla-only policy: never imply MapKit/OSRM was used when truck routing failed.
    func horizonRoutingFailureMessage(_ error: Error) -> String {
        if case RoutingServiceError.allProvidersFailed = error {
            return horizonRouteErrorValhallaUnavailable
        }
        return horizonRouteErrorUnableSafeRoute
    }

    /// Matches `RegionalSettingsManager` / `selectedLanguage` in `UserDefaults`.
    /// `nonisolated(unsafe)` keeps this readable from any isolation domain; `UserDefaults` is thread-safe for reads/writes.
    nonisolated(unsafe) static var persistedDriverChoice: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: "selectedLanguage"),
           let lang = AppLanguage.allCases.first(where: { $0.rawValue == raw }) {
            return lang
        }
        return .english
    }

    /// Speed compliance banner when GPS/telemetry exceeds policy-derived heavy-vehicle guidance.
    func truckSpeedComplianceMessage(currentFormatted: String, limitFormatted: String) -> String {
        switch self {
        case .english, .hindi, .arabic:
            return "Truck speed \(currentFormatted) is above local heavy-vehicle guidance (\(limitFormatted)). Reduce speed."
        case .portuguese:
            return "Velocidade \(currentFormatted) acima da referência para veículo pesado (\(limitFormatted)). Reduza."
        case .spanish, .spanishLatam:
            return "Velocidad \(currentFormatted) por encima de la referencia para vehículo pesado (\(limitFormatted)). Reduzca."
        case .french:
            return "Vitesse \(currentFormatted) au-dessus de la référence poids lourds (\(limitFormatted)). Ralentissez."
        case .german:
            return "Geschwindigkeit \(currentFormatted) über Schwerverkehr-Richtwert (\(limitFormatted)). Reduzieren."
        case .polish:
            return "Prędkość \(currentFormatted) powyżej wytycznej dla pojazdu ciężkiego (\(limitFormatted)). Zwolnij."
        case .russian:
            return "Скорость \(currentFormatted) выше ориентира для тяжёлого транспорта (\(limitFormatted)). Снизьте скорость."
        }
    }
}

// MARK: - Regional Settings Manager
@Observable
class RegionalSettingsManager {
    var currentRegion: SupportedRegion {
        didSet {
            UserDefaults.standard.set(currentRegion.rawValue, forKey: "selectedRegion")
            // App copy defaults to English until the driver explicitly picks a language in settings.
            if !UserDefaults.standard.bool(forKey: "languageManuallySet") {
                currentLanguage = .english
            }
        }
    }

    var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "selectedLanguage")
            UserDefaults.standard.set(true, forKey: "languageManuallySet")
        }
    }

    init() {
        // Detect region
        let detectedRegion: SupportedRegion
        if let savedRegion = UserDefaults.standard.string(forKey: "selectedRegion"),
           let region = SupportedRegion(rawValue: savedRegion) {
            detectedRegion = region
        } else {
            let localeRegion = Locale.current.region?.identifier ?? "US"
            let euCodes = ["AT","BE","BG","HR","CY","CZ","DK","EE","FI","FR",
                           "DE","GR","HU","IE","IT","LV","LT","LU","MT","NL",
                           "PL","PT","RO","SK","SI","ES","SE"]
            switch localeRegion {
            case "US": detectedRegion = .usa
            case "CA": detectedRegion = .canada
            case "MX": detectedRegion = .mexico
            case "BR": detectedRegion = .brazil
            case "GB": detectedRegion = .uk
            case "AU": detectedRegion = .australia
            default:   detectedRegion = euCodes.contains(localeRegion) ? .europe : .usa
            }
        }
        self.currentRegion = detectedRegion

        // Detect language: English until the driver saves a choice (region does not imply UI language).
        if let savedLang = UserDefaults.standard.string(forKey: "selectedLanguage"),
           let lang = AppLanguage(rawValue: savedLang) {
            self.currentLanguage = lang
        } else {
            self.currentLanguage = .english
        }
    }

    // MARK: - Formatting helpers
    func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = currentRegion.locale
        formatter.currencyCode = currentRegion.currency
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currentRegion.currencySymbol)\(String(format: "%.2f", amount))"
    }

    func formatDistance(_ meters: Double) -> String {
        currentRegion.formatDistance(meters)
    }

    func formatDistanceDirect(_ value: Double) -> String {
        // value is already in the region's unit (mi or km)
        return String(format: "%.1f %@", value, currentRegion.distanceUnit)
    }

    func formatFuel(_ fuel: Double) -> String {
        String(format: "%.2f %@", fuel, currentRegion.fuelUnit)
    }

    func formatSpeed(_ kmh: Double) -> String {
        currentRegion.formatSpeed(kmh)
    }

    func formatWeight(_ kg: Double) -> String {
        currentRegion.formatWeight(kg)
    }

    // Current HOS rules
    var hosRules: HOSRules { currentRegion.hosRules }

    // Current language shorthand
    var lang: AppLanguage { currentLanguage }
}
