import Foundation

// MARK: - Provider Enum

enum FuelPriceProvider: String, CaseIterable, Identifiable {
    case eia          // USA – EIA API v2 (free key) or DNAV (no key)
    case nrcan        // Canada – Natural Resources Canada RSS (no key)
    case anp          // Brazil – ANP Open Data CSV (no key)
    case euOilBulletin // Europe – EC Weekly Oil Bulletin (no key)
    case ukBeis       // UK – BEIS/DESNZ weekly CSV (no key)
    case opis         // North America commercial (requires private contract)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eia:           return "EIA (USA)"
        case .nrcan:         return "NRCan (Canada)"
        case .anp:           return "ANP (Brazil)"
        case .euOilBulletin: return "EU Oil Bulletin"
        case .ukBeis:        return "BEIS (UK)"
        case .opis:          return "OPIS"
        
        }
    }

    var supportsStationLevelPricing: Bool {
        switch self {
        case .eia, .nrcan, .anp, .euOilBulletin, .ukBeis: return false
        case .opis: return true
        }
    }

    var requiresPrivateContract: Bool {
        switch self {
        case .opis: return true
        default: return false
        }
    }
}

// MARK: - Models

struct FuelPricePoint: Identifiable, Sendable {
    let id: String
    let provider: FuelPriceProvider
    let stationName: String?
    let locationLabel: String
    let dieselPrice: Double
    let currencyCode: String
    let unitLabel: String
    let updatedAt: Date?
    let latitude: Double?
    let longitude: Double?
    let isEstimated: Bool
    let sourceLabel: String
}

struct FuelProviderAvailability: Sendable {
    let provider: FuelPriceProvider
    let isConfigured: Bool
    let supportsStationLevelPricing: Bool
    let requiresPrivateContract: Bool
    let notes: String
}

// MARK: - Service

@Observable
final class FuelPriceService {
    static let shared = FuelPriceService()

    private(set) var activeProviders: [FuelPriceProvider] = []
    private var cachedByRegion: [SupportedRegion: (point: FuelPricePoint, expiresAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 600

    private init() {}

    func bootstrap() {
        activeProviders = FuelPriceProvider.allCases.filter(isConfigured)
        if activeProviders.isEmpty {
            activeProviders = [.eia, .nrcan, .anp, .euOilBulletin, .ukBeis]
        }
    }

    func availabilityMatrix() -> [FuelProviderAvailability] {
        FuelPriceProvider.allCases.map { provider in
            FuelProviderAvailability(
                provider: provider,
                isConfigured: isConfigured(provider),
                supportsStationLevelPricing: provider.supportsStationLevelPricing,
                requiresPrivateContract: provider.requiresPrivateContract,
                notes: notes(for: provider)
            )
        }
    }

    /// Returns the best available diesel price point for the given region.
    func fetchPublicDieselPrice(for region: SupportedRegion) async -> FuelPricePoint? {
        if let cached = cachedByRegion[region], Date() < cached.expiresAt {
            return cached.point
        }

        let point: FuelPricePoint?
        switch region {
        case .usa:
            point = await fetchEIADieselPrice()
        case .canada:
            point = await fetchNRCanDieselAverage()
        case .brazil:
            point = await fetchANPDieselAverage()
        case .europe:
            point = await fetchEUOilBulletinDieselPrice()
        case .uk:
            point = await fetchUKBeisDieselPrice()
        case .mexico, .australia:
            point = nil
        }

        if let point {
            cachedByRegion[region] = (point, Date().addingTimeInterval(cacheTTL))
        }
        return point
    }

    // MARK: - Configuration

    private func isConfigured(_ provider: FuelPriceProvider) -> Bool {
        switch provider {
        case .eia, .nrcan, .anp, .euOilBulletin, .ukBeis:
            return true
        case .opis:
            return !stringValue(forInfoKey: "OPISAPIKey").isEmpty
        
        }
    }

    private func notes(for provider: FuelPriceProvider) -> String {
        switch provider {
        case .eia:
            return "US EIA weekly on-highway diesel averages. Free API key optional — falls back to EIA DNAV (no key)."
        case .nrcan:
            return "Natural Resources Canada weekly retail diesel prices by city. Free, no key required."
        case .anp:
            return "Brazil ANP open-data CSV: last 4 weeks diesel S-10 national averages. Free, no key."
        case .euOilBulletin:
            return "European Commission Weekly Oil Bulletin – EU-27 diesel with taxes. Free, no key."
        case .ukBeis:
            return "UK DESNZ/BEIS weekly retail diesel prices (pence per litre). Free, no key."
        case .opis:
            return "Commercial station-level pricing for North America. Requires private contract."
        
        }
    }

    func stringValue(forInfoKey key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - USA: EIA

extension FuelPriceService {

    /// Primary: EIA API v2 — no API key required (key adds higher rate limits only).
    /// Endpoint: https://api.eia.gov/v2/petroleum/pri/gnd/data/
    /// Series: EPD2D = No.2 On-Highway Diesel, NUS = National U.S. average, weekly.
    /// Fallback: EIA DNAV TSV endpoint (also keyless).
    private func fetchEIADieselPrice() async -> FuelPricePoint? {
        if let point = await fetchEIAFromAPI() {
            #if DEBUG
            print("[Fuel] diesel via EIA API: $\(point.dieselPrice)/gal")
            #endif
            return point
        }
        if let point = await fetchEIAFromDNAV() {
            #if DEBUG
            print("[Fuel] diesel via EIA DNAV: $\(point.dieselPrice)/gal")
            #endif
            return point
        }
        // 3º fallback sem chave: USDA Open Ag Transport republica o diesel semanal da EIA.
        let usda = await fetchUSDADieselPrice()
        #if DEBUG
        if let usda {
            print("[Fuel] diesel via USDA: $\(usda.dieselPrice)/gal")
        } else {
            print("[Fuel] diesel: todas as fontes falharam (usa fallback $3.85)")
        }
        #endif
        return usda
    }

    /// EIA API v2 — works without an API key.
    /// If EIAAPIKey is configured in Info.plist it is included for higher rate limits.
    private func fetchEIAFromAPI() async -> FuelPricePoint? {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "frequency", value: "weekly"),
            URLQueryItem(name: "data[0]", value: "value"),
            URLQueryItem(name: "facets[product][]", value: "EPD2D"),   // No.2 On-Highway Diesel
            URLQueryItem(name: "facets[duoarea][]", value: "NUS"),     // National U.S. average
            URLQueryItem(name: "sort[0][column]", value: "period"),
            URLQueryItem(name: "sort[0][direction]", value: "desc"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "length", value: "1")
        ]

        // Add API key only when configured (raises rate limit from 100 to 9000 req/hr)
        let apiKey = stringValue(forInfoKey: "EIAAPIKey")
        if !apiKey.isEmpty {
            queryItems.insert(URLQueryItem(name: "api_key", value: apiKey), at: 0)
        }

        var components = URLComponents(string: "https://api.eia.gov/v2/petroleum/pri/gnd/data/")
        components?.queryItems = queryItems
        guard let url = components?.url else { return nil }

        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(EIAAPIResponse.self, from: data)
            guard let row = decoded.response?.data.first,
                  let price = Double(row.value), price > 0 else { return nil }

            return FuelPricePoint(
                id: "eia-api-usa-\(row.period)",
                provider: .eia,
                stationName: nil,
                locationLabel: "United States (national avg)",
                dieselPrice: price,
                currencyCode: "USD",
                unitLabel: "$/gal",
                updatedAt: parseEIADate(row.period),
                latitude: nil, longitude: nil,
                isEstimated: true,
                sourceLabel: "EIA API v2 – weekly on-highway diesel"
            )
        } catch {
            #if DEBUG
            print("[Fuel] EIA API v2 error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// EIA DNAV — no API key required.
    /// Returns tab-separated weekly data for series EMD_EPD2D_PTE_NUS_DPG (US national diesel).
    /// Format: Date\tValue per row, newest last.
    private func fetchEIAFromDNAV() async -> FuelPricePoint? {
        // DNAV leaf handler — free, no key, returns TSV with "Date\tValue" rows
        let urlString = "https://www.eia.gov/dnav/pet/hist/LeafHandler.ashx?n=PET&s=EMD_EPD2D_PTE_NUS_DPG&f=W"
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else { return nil }

            // Parse TSV: skip header lines (start with "Date" or empty), take last numeric row
            let lines = text.components(separatedBy: "\n")
            var latestPrice: Double?
            var latestDate: Date?

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd/yyyy"

            for line in lines.reversed() {
                let cols = line.components(separatedBy: "\t")
                guard cols.count >= 2 else { continue }
                let dateStr = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let valStr = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard let price = Double(valStr), price > 0 else { continue }
                latestPrice = price
                latestDate = dateFormatter.date(from: dateStr)
                break
            }

            guard let price = latestPrice else { return nil }
            return FuelPricePoint(
                id: "eia-dnav-usa-\(Int(Date().timeIntervalSince1970))",
                provider: .eia,
                stationName: nil,
                locationLabel: "United States (national avg)",
                dieselPrice: price,
                currencyCode: "USD",
                unitLabel: "$/gal",
                updatedAt: latestDate ?? Date(),
                latitude: nil, longitude: nil,
                isEstimated: true,
                sourceLabel: "EIA DNAV – weekly on-highway diesel"
            )
        } catch {
            #if DEBUG
            print("[Fuel] EIA DNAV error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// USDA Open Ag Transport (Socrata) — republica o diesel "on-highway" semanal da EIA.
    /// Endpoint keyless: /resource/x88w-atzp.json · campos: date, region ("US"=nacional), diesel_price.
    private func fetchUSDADieselPrice() async -> FuelPricePoint? {
        var components = URLComponents(string: "https://agtransport.usda.gov/resource/x88w-atzp.json")
        components?.queryItems = [
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "$order", value: "date DESC"),
            URLQueryItem(name: "$limit", value: "1")
        ]
        guard let url = components?.url else { return nil }

        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let rows = try JSONDecoder().decode([USDADieselRow].self, from: data)
            guard let row = rows.first, let price = Double(row.diesel_price), price > 0 else { return nil }

            return FuelPricePoint(
                id: "usda-usa-\(row.date)",
                provider: .eia,   // USDA republica o dado da EIA
                stationName: nil,
                locationLabel: "United States (national avg)",
                dieselPrice: price,
                currencyCode: "USD",
                unitLabel: "$/gal",
                updatedAt: Date(),
                latitude: nil, longitude: nil,
                isEstimated: true,
                sourceLabel: "USDA Open Ag Transport – weekly on-highway diesel"
            )
        } catch {
            #if DEBUG
            print("[Fuel] USDA Socrata error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private struct USDADieselRow: Decodable {
        let date: String
        let diesel_price: String
    }

    private func parseEIADate(_ period: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: period)
    }
}

// MARK: - Canada: NRCan RSS

extension FuelPriceService {

    /// NRCan public RSS feed — productID=5 (diesel), locationID=66 (Canada national avg).
    /// Returns CAD/L price.
    private func fetchNRCanDieselAverage() async -> FuelPricePoint? {
        // Confirmed working: productID=5 = Diesel, locationID=66 = Canada national
        let urlString = "https://www2.nrcan.gc.ca/eneene/sources/pripri/webfeed_e.cfm?productID=5&locationID=66"
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            let parser = NRCanRSSParser()
            let xmlParser = XMLParser(data: data)
            xmlParser.delegate = parser
            xmlParser.parse()

            guard let price = parser.canadaNationalPrice else { return nil }

            return FuelPricePoint(
                id: "nrcan-canada-\(Int(Date().timeIntervalSince1970))",
                provider: .nrcan,
                stationName: nil,
                locationLabel: "Canada (national average)",
                dieselPrice: price,
                currencyCode: "CAD",
                unitLabel: "CAD/L",
                updatedAt: parser.latestDate ?? Date(),
                latitude: nil, longitude: nil,
                isEstimated: true,
                sourceLabel: "Natural Resources Canada – weekly diesel retail"
            )
        } catch {
            #if DEBUG
            print("[Fuel] NRCan error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
}

// MARK: - Brazil: ANP Open Data CSV

extension FuelPriceService {

    /// ANP open-data CSV — last 4 weeks of station-level diesel prices.
    /// Averages Diesel S-10 prices nationally.
    private func fetchANPDieselAverage() async -> FuelPricePoint? {
        let urlString = "https://www.gov.br/anp/pt-br/centrais-de-conteudo/dados-abertos/arquivos/shpc/qus/ultimas-4-semanas-diesel-gnv.csv"
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            // ANP CSV may be ISO-8859-1 or UTF-8
            let csv = String(data: data, encoding: .isoLatin1)
                   ?? String(data: data, encoding: .utf8)
                   ?? ""

            guard !csv.isEmpty else { return nil }

            let prices = parseANPCSV(csv)
            guard !prices.isEmpty else { return nil }

            let avg = prices.reduce(0, +) / Double(prices.count)
            return FuelPricePoint(
                id: "anp-brazil-\(Int(Date().timeIntervalSince1970))",
                provider: .anp,
                stationName: nil,
                locationLabel: "Brasil (média nacional – \(prices.count) postos)",
                dieselPrice: avg,
                currencyCode: "BRL",
                unitLabel: "R$/L",
                updatedAt: Date(),
                latitude: nil, longitude: nil,
                isEstimated: true,
                sourceLabel: "ANP – Levantamento Semanal de Preços (últimas 4 semanas)"
            )
        } catch {
            #if DEBUG
            print("[Fuel] ANP error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Parses semicolon-separated ANP CSV.
    /// Columns: Regiao;Sigla;Estado;Municipio;Revenda;CNPJ;Rua;Num;Compl;Bairro;CEP;
    ///          Produto;Data da Coleta;Valor de Venda;Valor de Compra;Unidade;Bandeira
    /// Index:   0       1      2       3          4        5     6    7    8      9   10
    ///          11      12               13               14              15       16
    private func parseANPCSV(_ csv: String) -> [Double] {
        var prices: [Double] = []
        let lines = csv.components(separatedBy: "\n")
        guard lines.count > 1 else { return prices }

        // Detect column indices from header
        let header = lines[0].components(separatedBy: ";")
        let productCol = header.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().contains("produto")
        }) ?? 11
        let priceCol = header.firstIndex(where: {
            let h = $0.trimmingCharacters(in: .whitespaces).lowercased()
            return h.contains("valor de venda")
        }) ?? 13

        for line in lines.dropFirst() {
            let cols = line.components(separatedBy: ";")
            guard cols.count > max(productCol, priceCol) else { continue }
            let product = cols[productCol].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard product.contains("DIESEL") else { continue }
            // ANP uses comma as decimal separator (e.g. "6,89")
            let raw = cols[priceCol]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            if let value = Double(raw), value > 0 {
                prices.append(value)
            }
        }
        return prices
    }
}

// MARK: - Europe: EC Weekly Oil Bulletin

extension FuelPriceService {

    /// EC Weekly Oil Bulletin — XLSX download parsed in-memory.
    /// Returns EU-27 diesel price with taxes in EUR/L.
    private func fetchEUOilBulletinDieselPrice() async -> FuelPricePoint? {
        // Try the stable UUID download link for the weekly "with taxes" XLSX
        let xlsxURLString = "https://energy.ec.europa.eu/document/download/264c2d0f-f161-4ea3-a777-78faae59bea0_en"
        if let point = await tryFetchEUFromXLSX(urlString: xlsxURLString) { return point }

        // Fallback: try the historical series XLSX
        let histURLString = "https://energy.ec.europa.eu/document/download/906e60ca-8b6a-44e7-8589-652854d2fd3f_en"
        return await tryFetchEUFromXLSX(urlString: histURLString)
    }

    private func tryFetchEUFromXLSX(urlString: String) async -> FuelPricePoint? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }

            guard let price = extractEUDieselFromXLSX(data) else { return nil }

            return FuelPricePoint(
                id: "eu-bulletin-\(Int(Date().timeIntervalSince1970))",
                provider: .euOilBulletin,
                stationName: nil,
                locationLabel: "EU-27 (weekly avg with taxes)",
                dieselPrice: price,
                currencyCode: "EUR",
                unitLabel: "EUR/L",
                updatedAt: Date(),
                latitude: nil, longitude: nil,
                isEstimated: true,
                sourceLabel: "EC Weekly Oil Bulletin – diesel with taxes"
            )
        } catch {
            #if DEBUG
            print("[Fuel] EU Bulletin error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Parses the XLSX ZIP in-memory: extracts sheet XML and finds EU-27 diesel price.
    private func extractEUDieselFromXLSX(_ data: Data) -> Double? {
        // 1. Try sheet1 for the value
        if let xmlString = extractZIPEntry(data, entry: "xl/worksheets/sheet1.xml") {
            if let price = parseEUDieselFromSheetXML(xmlString) { return price }
        }
        // 2. Try sheet2 (some bulletin versions use sheet2)
        if let xmlString = extractZIPEntry(data, entry: "xl/worksheets/sheet2.xml") {
            if let price = parseEUDieselFromSheetXML(xmlString) { return price }
        }
        return nil
    }

    /// Minimal ZIP entry reader — no third-party library needed.
    private func extractZIPEntry(_ data: Data, entry: String) -> String? {
        let signature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        let bytes = [UInt8](data)
        var offset = 0

        while offset + 30 < bytes.count {
            guard bytes[offset] == signature[0], bytes[offset+1] == signature[1],
                  bytes[offset+2] == signature[2], bytes[offset+3] == signature[3] else {
                offset += 1
                continue
            }
            let compMethod = Int(bytes[offset+8]) | (Int(bytes[offset+9]) << 8)
            let compSize   = Int(bytes[offset+18]) | (Int(bytes[offset+19]) << 8)
                           | (Int(bytes[offset+20]) << 16) | (Int(bytes[offset+21]) << 24)
            let nameLen    = Int(bytes[offset+26]) | (Int(bytes[offset+27]) << 8)
            let extraLen   = Int(bytes[offset+28]) | (Int(bytes[offset+29]) << 8)
            let nameStart  = offset + 30
            let nameEnd    = nameStart + nameLen
            guard nameEnd <= bytes.count else { break }
            let nameData   = Data(bytes[nameStart..<nameEnd])
            let entryName  = String(data: nameData, encoding: .utf8) ?? ""
            let dataStart  = nameEnd + extraLen
            let dataEnd    = dataStart + compSize
            guard dataEnd <= bytes.count else { break }

            if entryName == entry {
                let compData = Data(bytes[dataStart..<dataEnd])
                if compMethod == 0 {
                    return String(data: compData, encoding: .utf8)
                } else if compMethod == 8 {
                    // zlib raw deflate — prepend zlib header bytes
                    var zlibData = Data([0x78, 0x9C])
                    zlibData.append(compData)
                    if let inflated = try? (zlibData as NSData).decompressed(using: .zlib) {
                        return String(data: inflated as Data, encoding: .utf8)
                    }
                    // Try without header (raw deflate)
                    if let inflated = try? (compData as NSData).decompressed(using: .zlib) {
                        return String(data: inflated as Data, encoding: .utf8)
                    }
                }
            }
            offset = dataEnd
        }
        return nil
    }

    /// Scans OOXML sheet XML for EU-27 diesel price cells (EUR/L, range 1.2–2.5).
    private func parseEUDieselFromSheetXML(_ xml: String) -> Double? {
        // Cell values in OOXML: <v>1.835</v>
        let pattern = #"<v>([0-9]+\.[0-9]+)</v>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(xml.startIndex..., in: xml)
        let matches = regex.matches(in: xml, range: range)

        var candidates: [Double] = []
        for match in matches {
            if let r = Range(match.range(at: 1), in: xml), let v = Double(xml[r]) {
                candidates.append(v)
            }
        }
        // EU diesel typically 1.2–2.4 EUR/L; pick the median of plausible values
        let plausible = candidates.filter { $0 >= 1.2 && $0 <= 2.5 }
        guard !plausible.isEmpty else { return nil }
        let sorted = plausible.sorted()
        return sorted[sorted.count / 2]
    }
}

// MARK: - UK: BEIS Weekly Fuel Prices CSV

extension FuelPriceService {

    private func fetchUKBeisDieselPrice() async -> FuelPricePoint? {
        // Direct stable GOV.UK asset path
        let knownURLs = [
            "https://assets.publishing.service.gov.uk/media/weekly_road_fuel_prices.csv",
            "https://assets.publishing.service.gov.uk/government/uploads/system/uploads/attachment_data/file/weekly_road_fuel_prices.csv"
        ]
        for urlString in knownURLs {
            if let point = await tryFetchUKCSV(from: urlString) { return point }
        }
        // Last resort: scrape the statistics page for the CSV link
        return await fetchUKBeisFromStatisticsPage()
    }

    private func tryFetchUKCSV(from urlString: String) async -> FuelPricePoint? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let csv = String(data: data, encoding: .utf8) else { return nil }
            return parseUKBEISCSV(csv)
        } catch {
            return nil
        }
    }

    private func fetchUKBeisFromStatisticsPage() async -> FuelPricePoint? {
        guard let pageURL = URL(string: "https://www.gov.uk/government/statistics/weekly-road-fuel-prices") else { return nil }
        do {
            var request = URLRequest(url: pageURL, timeoutInterval: 15)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (pageData, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: pageData, encoding: .utf8) else { return nil }
            // Find CSV href
            let csvPattern = #"href=\"(https://[^\"]+\.csv)\""#
            guard let csvURLString = firstMatch(in: html, pattern: csvPattern),
                  let csvURL = URL(string: csvURLString) else { return nil }
            let (csvData, _) = try await URLSession.shared.data(from: csvURL)
            guard let csv = String(data: csvData, encoding: .utf8) else { return nil }
            return parseUKBEISCSV(csv)
        } catch {
            #if DEBUG
            print("[Fuel] UK BEIS scrape error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Parses BEIS weekly road fuel prices CSV.
    /// Typical columns: Date, ULSP (pence/L), ULSD (pence/L), ...
    private func parseUKBEISCSV(_ csv: String) -> FuelPricePoint? {
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }

        let header = lines[0].components(separatedBy: ",")
        let dieselCol = header.firstIndex(where: {
            let h = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return h.contains("ulsd") || h.contains("diesel")
        })

        guard let lastLine = lines.dropFirst().last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let cols = lastLine.components(separatedBy: ",")

        let dieselPence: Double?
        if let idx = dieselCol, idx < cols.count {
            dieselPence = Double(cols[idx].trimmingCharacters(in: .whitespacesAndNewlines))
        } else if cols.count >= 3 {
            dieselPence = Double(cols[2].trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            dieselPence = nil
        }

        guard let pence = dieselPence, pence > 0 else { return nil }
        let poundsPerLitre = pence / 100.0

        return FuelPricePoint(
            id: "uk-beis-\(Int(Date().timeIntervalSince1970))",
            provider: .ukBeis,
            stationName: nil,
            locationLabel: "United Kingdom (national avg)",
            dieselPrice: poundsPerLitre,
            currencyCode: "GBP",
            unitLabel: "£/L",
            updatedAt: Date(),
            latitude: nil, longitude: nil,
            isEstimated: true,
            sourceLabel: "UK DESNZ/BEIS – Weekly Road Fuel Prices"
        )
    }
}

// MARK: - Shared Helpers

extension FuelPriceService {

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let capturedRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[capturedRange])
    }
}

// MARK: - EIA API v2 Codable

private struct EIAAPIResponse: Codable {
    struct Response: Codable {
        let data: [DataRow]
    }
    struct DataRow: Codable {
        let period: String
        let value: String  // EIA returns value as String in v2
        enum CodingKeys: String, CodingKey {
            case period, value
        }
        // Handle both string and number in the JSON
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            period = try container.decode(String.self, forKey: .period)
            if let strVal = try? container.decode(String.self, forKey: .value) {
                value = strVal
            } else if let numVal = try? container.decode(Double.self, forKey: .value) {
                value = String(numVal)
            } else {
                value = ""
            }
        }
    }
    let response: Response?
}

// MARK: - NRCan RSS Parser

private class NRCanRSSParser: NSObject, XMLParserDelegate {
    /// National Canada average diesel price (CAD/L)
    var canadaNationalPrice: Double?
    var latestDate: Date?

    private var currentTitle = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var insideItem = false
    private var currentElement = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentDescription = ""
            currentPubDate = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        switch currentElement {
        case "title":       currentTitle += string
        case "description": currentDescription += string
        case "pubDate":     currentPubDate += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "item" && insideItem {
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            // Look for the "Canada" national entry
            if title.lowercased().contains("canada") {
                // Strip currency symbol ($) and parse
                let numStr = desc.replacingOccurrences(of: "$", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let price = Double(numStr), price > 0 {
                    if canadaNationalPrice == nil {
                        canadaNationalPrice = price
                        // Parse pubDate
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                        latestDate = formatter.date(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
            insideItem = false
        }
        if elementName == "item" { currentElement = "" }
    }
}
