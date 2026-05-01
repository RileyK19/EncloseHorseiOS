//
//  PuzzleScraper.swift
//  EncloseHorse
//
//  Created by Riley Koo on 2/23/26.
//

import Foundation
import WebKit

enum ScraperError: LocalizedError {
    case timeout
    case parsingFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .timeout:              return "Timed out waiting for puzzle to load."
        case .parsingFailed(let m): return "Parsing failed: \(m)"
        case .networkError(let m):  return "Network error: \(m)"
        }
    }
}

@MainActor
class PuzzleScraper: NSObject, WKNavigationDelegate {

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<PuzzleData, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var currentDateStr: String = ""
    var currentWebView: WKWebView? { webView }

    // MARK: - Public entry point
    func fetchPuzzle(for date: Date) async throws -> PuzzleData {
        let dateStr = isoDate(date)

        // 1. Supabase cache
        if let jsonString = await SupabaseClient.fetchDailyPuzzle(date: dateStr),
           let data = jsonString.data(using: .utf8),
           let puzzle = try? JSONDecoder().decode(PuzzleData.self, from: data) {
            print("✅ [PuzzleScraper] loaded from Supabase: \(dateStr)")
            return puzzle
        }

        // 2. Scrape (gets puzzle + optimal together)
        print("🌐 [PuzzleScraper] scraping: \(dateStr)")
        if let scraped = try? await scrape(for: date, dateStr: dateStr) {
            // Upload puzzle to Supabase
            if let encoded = try? JSONEncoder().encode(scraped),
               let jsonString = String(data: encoded, encoding: .utf8) {
                let dayNum = daysSinceEpoch(for: date)
                await SupabaseClient.uploadDailyPuzzle(date: dateStr, puzzleNumber: dayNum, puzzleJSON: jsonString)
            }
            // Upload optimal separately
            if scraped.optimalScore > 0 {
                await SupabaseClient.uploadOptimalScore(date: dateStr, optimal: scraped.optimalScore)
            }
            return scraped
        }

        // 3. API fallback
        print("⚠️ [PuzzleScraper] scrape failed, falling back to API: \(dateStr)")
        return try await fetchFromAPI(dateStr: dateStr)
    }

    // MARK: - WKWebView scrape
    private func scrape(for date: Date, dateStr: String) async throws -> PuzzleData {
        currentDateStr = dateStr
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            setupWebView(for: date, dateStr: dateStr)
        }
    }

    private func setupWebView(for date: Date, dateStr: String) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            window.addSubview(wv)
            wv.isHidden = true
        }

        let urlString = Constants.baseURL + "play/\(dateStr)"
        guard let url = URL(string: urlString) else {
            continuation?.resume(throwing: ScraperError.networkError("Bad URL"))
            continuation = nil
            return
        }

        wv.load(URLRequest(url: url))

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled else { return }
            self.continuation?.resume(throwing: ScraperError.timeout)
            self.continuation = nil
            self.cleanup()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.extractPuzzleData(from: webView)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async {
            guard self.continuation != nil else { return }
            self.continuation?.resume(throwing: ScraperError.networkError(error.localizedDescription))
            self.continuation = nil
            self.cleanup()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async {
            guard self.continuation != nil else { return }
            self.continuation?.resume(throwing: ScraperError.networkError(error.localizedDescription))
            self.continuation = nil
            self.cleanup()
        }
    }

    // MARK: - JS extraction
    private let extractionJS = """
    (function() {
        try {
            var level = window.__LEVEL__;
            if (!level || !level.map) {
                return JSON.stringify({ error: '__LEVEL__ not found or missing map key' });
            }
            return JSON.stringify({
                success:   true,
                map:       level.map,
                budget:    level.budget,
                dayNumber: level.dayNumber,
                optimal:   level.optimal || level.optimalScore || 0
            });
        } catch(e) {
            return JSON.stringify({ error: e.message });
        }
    })();
    """

    private func extractPuzzleData(from webView: WKWebView) {
        webView.evaluateJavaScript(extractionJS) { [weak self] result, error in
            guard let self else { return }
            defer { self.continuation = nil; self.cleanup() }

            if let error {
                self.continuation?.resume(throwing: ScraperError.parsingFailed(error.localizedDescription))
                return
            }

            guard let jsonString = result as? String,
                  let jsonData = jsonString.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                self.continuation?.resume(throwing: ScraperError.parsingFailed("Could not parse JS result"))
                return
            }

            if let errMsg = parsed["error"] as? String {
                self.continuation?.resume(throwing: ScraperError.parsingFailed(errMsg))
                return
            }

            guard parsed["success"] != nil,
                  let mapString = parsed["map"] as? String else {
                self.continuation?.resume(throwing: ScraperError.parsingFailed("Missing map"))
                return
            }

            let budget   = parsed["budget"]    as? Int ?? 10
            let optimal  = parsed["optimal"]   as? Int ?? 0
            let dayNum   = parsed["dayNumber"] as? Int ?? 0
            print("✅ [PuzzleScraper] Day \(dayNum) budget=\(budget) optimal=\(optimal)")

            let puzzle = self.parsePuzzle(from: mapString, wallCount: budget, optimalScore: optimal)
            self.continuation?.resume(returning: puzzle)
        }
    }

    // MARK: - API fallback
    private func fetchFromAPI(dateStr: String) async throws -> PuzzleData {
        guard let url = URL(string: Constants.baseURL + "api/daily/\(dateStr)") else {
            throw ScraperError.networkError("Bad URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ScraperError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mapString = json["map"] as? String else {
            throw ScraperError.parsingFailed("Missing map field")
        }
        let wallCount   = json["budget"]  as? Int ?? 10
        let optimalScore = json["optimal"] as? Int ?? 0
        print("✅ [PuzzleScraper] API fallback: \(dateStr) budget=\(wallCount) optimal=\(optimalScore)")
        return parsePuzzle(from: mapString, wallCount: wallCount, optimalScore: optimalScore)
    }

    // MARK: - Map parsing
    private func parsePuzzle(from mapString: String, wallCount: Int, optimalScore: Int) -> PuzzleData {
        let rows = mapString.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !rows.isEmpty else { return makeFallbackPuzzle() }

        let numRows = rows.count
        let numCols = rows.map { $0.count }.max() ?? 0

        var tiles: [[String]] = rows.map { row in
            row.map { ch -> String in
                switch ch {
                case "~": return "w"
                case "H": return "H"
                case "C": return "c"
                case "S": return "b"
                case "G": return "gem"
                case "0","1","2","3","4","5","6","7","8","9": return "portal_\(ch)"
                default:  return "g"
                }
            }
        }

        for r in 0..<numRows {
            while tiles[r].count < numCols { tiles[r].append("g") }
        }

        var horseRow = 0, horseCol = 0
        outer: for (r, row) in tiles.enumerated() {
            for (c, tile) in row.enumerated() {
                if tile == "H" { horseRow = r; horseCol = c; break outer }
            }
        }

        return PuzzleData(rows: numRows, cols: numCols, tiles: tiles,
                          wallCount: wallCount, horseRow: horseRow, horseCol: horseCol,
                          optimalScore: optimalScore)
    }

    private func makeFallbackPuzzle() -> PuzzleData {
        let tiles: [[String]] = [
            ["g","g","g","g","g","g","g","g"],
            ["g","g","w","w","g","g","g","g"],
            ["g","g","w","g","g","g","g","g"],
            ["g","g","g","g","H","g","g","g"],
            ["g","g","g","g","g","g","w","g"],
            ["g","g","g","c","g","g","w","g"],
            ["g","g","g","g","g","g","g","g"],
            ["g","g","g","g","g","g","g","g"],
        ]
        return PuzzleData(rows: 8, cols: 8, tiles: tiles, wallCount: 10,
                          horseRow: 3, horseCol: 4, optimalScore: 0)
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.removeFromSuperview()
        webView?.navigationDelegate = nil
        webView = nil
    }

    // MARK: - Date helpers
    func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    func daysSinceEpoch(for date: Date = .now) -> Int {
        let ref = Calendar.current.startOfDay(
            for: DateComponents(calendar: .current, year: 2025, month: 12, day: 30).date ?? .now
        )
        let days = Calendar.current.dateComponents([.day], from: ref, to: date).day ?? 0
        return max(1, days + 1)
    }
    
    func parseMap(_ mapString: String, wallCount: Int, optimalScore: Int) -> PuzzleData {
        parsePuzzle(from: mapString, wallCount: wallCount, optimalScore: optimalScore)
    }
    
    func scrapeOptimal(for date: Date) async -> Int {
        let dateStr = isoDate(date)
        print("🌐 [PuzzleScraper] scraping optimal for \(dateStr)")
        guard let puzzle = try? await scrape(for: date, dateStr: dateStr) else { return 0 }
        return puzzle.optimalScore
    }
}
