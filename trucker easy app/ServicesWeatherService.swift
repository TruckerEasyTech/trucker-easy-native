import Foundation
import CoreLocation

// MARK: - Weather API Configuration
// Using OpenWeatherMap One Call API 3.0
// Sign up free at: https://openweathermap.org/api
// Add your key below — free tier: 1,000 calls/day
private enum WeatherAPIConfig {
    // Reads from Info.plist key "OpenWeatherMapAPIKey"
    static var apiKey: String {
        Bundle.main.object(forInfoDictionaryKey: "OpenWeatherMapAPIKey") as? String ?? ""
    }
    static let baseURL = "https://api.openweathermap.org/data/2.5/weather"
    static let oneCallURL = "https://api.openweathermap.org/data/3.0/onecall"
}

// NOTE: TruckWeather and WeatherDanger structs are defined in ViewsWeighStationWeatherShare.swift
// This file only adds the real network service layer on top.

// MARK: - Weather Models (from OpenWeatherMap)

struct OWMCurrentResponse: Decodable {
    let weather: [OWMWeatherDescription]
    let main: OWMMain
    let wind: OWMWind
    let visibility: Int?
    let name: String?
    let dt: Int

    struct OWMWeatherDescription: Decodable {
        let id: Int
        let main: String
        let description: String
        let icon: String
    }

    struct OWMMain: Decodable {
        let temp: Double
        let feels_like: Double
        let humidity: Int
        let pressure: Int
    }

    struct OWMWind: Decodable {
        let speed: Double   // m/s
        let gust: Double?
        let deg: Int?
    }
}

import SwiftUI

// MARK: - Real Weather Service

@Observable
final class RealWeatherService {
    static let shared = RealWeatherService()

    private(set) var currentWeather: TruckWeather?
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    private var lastCoordinate: CLLocationCoordinate2D?

    // Cache: don't refetch if same location and < 10 minutes old
    private var cacheExpiry: Date?

    private init() {}

    /// Fetch weather for coordinate using real provider only.
    func refresh(for coordinate: CLLocationCoordinate2D) async {
        guard !isLoading else { return }

        // Check cache
        if let expiry = cacheExpiry, Date() < expiry,
           currentWeather != nil,
           isSameLocation(coordinate) {
            return
        }

        isLoading = true
        errorMessage = nil
        lastCoordinate = coordinate

        guard !WeatherAPIConfig.apiKey.isEmpty else {
            await MainActor.run {
                self.currentWeather = nil
                self.errorMessage = "OpenWeatherMapAPIKey is missing"
                self.isLoading = false
                self.cacheExpiry = nil
            }
            return
        }

        await loadRealWeather(coordinate: coordinate)
    }

    // MARK: - Real API Call

    private func loadRealWeather(coordinate: CLLocationCoordinate2D) async {
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        let key = WeatherAPIConfig.apiKey

        let urlString = "\(WeatherAPIConfig.baseURL)?lat=\(lat)&lon=\(lon)&appid=\(key)&units=imperial"
        guard let url = URL(string: urlString) else {
            setError("Invalid URL")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                await MainActor.run {
                    self.currentWeather = nil
                    self.errorMessage = "Weather provider returned status \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                    self.isLoading = false
                    self.cacheExpiry = nil
                }
                return
            }
            let owm = try JSONDecoder().decode(OWMCurrentResponse.self, from: data)
            let weather = convert(owm: owm)
            await MainActor.run {
                self.currentWeather = weather
                self.lastUpdated = Date()
                self.cacheExpiry = Calendar.current.date(byAdding: .minute, value: 10, to: Date())
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.currentWeather = nil
                self.errorMessage = "Weather request failed: \(error.localizedDescription)"
                self.isLoading = false
                self.cacheExpiry = nil
            }
        }
    }

    // MARK: - Converter: OWM → TruckWeather

    private func convert(owm: OWMCurrentResponse) -> TruckWeather {
        let desc        = owm.weather.first?.main ?? "Clear"
        let icon        = sfSymbol(for: owm.weather.first?.icon ?? "01d")
        let tempF       = owm.main.temp         // imperial (we set units=imperial)
        let windMPH     = owm.wind.speed
        let gustMPH     = owm.wind.gust         // optional Double?
        let visMiles    = Double(owm.visibility ?? 10000) / 1609.344

        return TruckWeather(
            condition: desc.capitalized,
            temperatureF: tempF,
            windSpeedMPH: windMPH,
            windGustMPH: gustMPH,
            visibility: visMiles,
            precipChance: 0,    // /weather endpoint has no precip%; use One Call API for that
            icon: icon
        )
    }

    // MARK: - OWM icon code → SF Symbol

    private func sfSymbol(for code: String) -> String {
        let isNight = code.hasSuffix("n")
        let prefix = String(code.prefix(2))
        switch prefix {
        case "01": return isNight ? "moon.stars.fill"       : "sun.max.fill"
        case "02": return isNight ? "cloud.moon.fill"       : "cloud.sun.fill"
        case "03": return "cloud.fill"
        case "04": return "smoke.fill"
        case "09": return "cloud.drizzle.fill"
        case "10": return isNight ? "cloud.moon.rain.fill"  : "cloud.sun.rain.fill"
        case "11": return "cloud.bolt.rain.fill"
        case "13": return "snowflake"
        case "50": return "cloud.fog.fill"
        default:   return "cloud.sun.fill"
        }
    }

    private func isSameLocation(_ coord: CLLocationCoordinate2D) -> Bool {
        guard let last = lastCoordinate else { return false }
        let latDiff = abs(coord.latitude  - last.latitude)
        let lonDiff = abs(coord.longitude - last.longitude)
        return latDiff < 0.05 && lonDiff < 0.05
    }

    private func setError(_ msg: String) {
        errorMessage = msg
        isLoading = false
    }
}
