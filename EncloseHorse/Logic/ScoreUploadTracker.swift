//
//  ScoreUploadTracker.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/9/26.
//


//
//  ScoreUploadTracker.swift
//  EncloseHorse
//
//  Created by Riley Koo on 3/9/26.
//

import Foundation

/// Tracks which puzzle dates have been successfully uploaded to Supabase.
/// Stored in UserDefaults as a Set<String> of "yyyy-MM-dd" date strings.
/// This lets syncPendingScores skip dates it already knows are in the DB,
/// and only fall back to a live DB check for genuinely uncertain ones.
final class ScoreUploadTracker {
    static let shared = ScoreUploadTracker()

    private let key = "uploaded_daily_score_dates"

    private var uploadedDates: Set<String> {
        get {
            let arr = UserDefaults.standard.stringArray(forKey: key) ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: key)
        }
    }

    func isUploaded(date: String) -> Bool {
        uploadedDates.contains(date)
    }

    func markUploaded(date: String) {
        var current = uploadedDates
        current.insert(date)
        uploadedDates = current
    }

    /// Call if you need to force a re-sync for a specific date (e.g. score was updated)
    func clearUploaded(date: String) {
        var current = uploadedDates
        current.remove(date)
        uploadedDates = current
    }
}