import Combine
import Foundation
import UIKit

final class AdvertManager: ObservableObject {
    static let shared = AdvertManager()

    @Published private(set) var adverts: [Advert] = []

    private let storageKey = "neighborhub.local.adverts.v1"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        load()

        // Start remote watcher and merge remote adverts when available
        FirebaseManager.shared.watchAdverts { [weak self] remote in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // merge by id: update existing adverts or insert new ones
                var localById = Dictionary(uniqueKeysWithValues: self.adverts.map { ($0.id, $0) })
                for r in remote {
                    if let local = localById[r.id] {
                        // prefer the more recent createdAt; but preserve local disk paths and in-memory imageDatas
                        var merged = r
                        if r.createdAt > local.createdAt {
                            // remote is newer, but ensure we don't drop local cached images
                            if let localPaths = local.imageLocalPaths, !localPaths.isEmpty {
                                merged.imageLocalPaths = localPaths
                            }
                            if let localPath = local.imageLocalPath, merged.imageLocalPath == nil {
                                merged.imageLocalPath = localPath
                            }
                            if let localDatas = local.imageDatas,
                                merged.imageDatas == nil || merged.imageDatas!.isEmpty
                            {
                                merged.imageDatas = localDatas
                            }
                            // prefer remote storage URLs if present, otherwise keep local ones
                            if merged.imageStorageURL == nil {
                                merged.imageStorageURL = local.imageStorageURL
                            }
                            if merged.imageStorageURLs == nil || merged.imageStorageURLs!.isEmpty {
                                merged.imageStorageURLs = local.imageStorageURLs
                            }
                            localById[r.id] = merged
                        } else {
                            // local is newer; keep local but update any missing remote metadata
                            var kept = local
                            if kept.imageCount == nil { kept.imageCount = r.imageCount }
                            if kept.imagesPendingUpload == nil {
                                kept.imagesPendingUpload = r.imagesPendingUpload
                            }
                            if kept.imageStorageURL == nil {
                                kept.imageStorageURL = r.imageStorageURL
                            }
                            if kept.imageStorageURLs == nil || kept.imageStorageURLs!.isEmpty {
                                kept.imageStorageURLs = r.imageStorageURLs
                            }
                            localById[r.id] = kept
                        }
                    } else {
                        localById[r.id] = r
                    }
                }
                // preserve local order where possible, append new remote items by date
                var merged: [Advert] = []
                for existing in self.adverts {
                    if let v = localById[existing.id] {
                        merged.append(v)
                        localById.removeValue(forKey: existing.id)
                    }
                }
                let remaining = localById.values.sorted { $0.createdAt > $1.createdAt }
                merged = remaining + merged
                self.adverts = merged
            }
        }

        // Persist on change
        $adverts
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)

        // Kick off background uploader to sync any pending local images
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.runBackgroundUploader()
        }
    }

    // MARK: - CRUD

    func create(_ advert: Advert) {
        adverts.insert(advert, at: 0)
        // Persist remotely (optimistic local change already applied)
        print("[AdvertManager] creating advert id=\(advert.id) title=\(advert.title)")
        FirebaseManager.shared.createOrUpdateAdvert(advert) {
            [weak self] err, primaryURL, additional in
            if let err = err {
                print("Advert upload error: \(err)")
            } else {
                print("[AdvertManager] create remote success id=\(advert.id)")
                // If we received urls, update local advert immediately to reflect remote storage urls
                if primaryURL != nil || additional != nil {
                    DispatchQueue.main.async {
                        if let idx = self?.adverts.firstIndex(where: { $0.id == advert.id }) {
                            var copy = self!.adverts[idx]
                            if let p = primaryURL { copy.imageStorageURL = p }
                            if let a = additional { copy.imageStorageURLs = a }
                            self?.adverts[idx] = copy
                        }
                        // clear retry counter
                        self?.uploadRetries.removeValue(forKey: advert.id)
                    }
                }
            }
        }

        // Trigger background uploader for this newly created advert
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.runBackgroundUploader()
        }
    }

    func update(_ advert: Advert) {
        guard let idx = adverts.firstIndex(where: { $0.id == advert.id }) else { return }
        adverts[idx] = advert
        print("[AdvertManager] updating advert id=\(advert.id)")
        FirebaseManager.shared.createOrUpdateAdvert(advert) {
            [weak self] err, primaryURL, additional in
            if let err = err {
                print("Advert update error: \(err)")
            } else {
                print("[AdvertManager] update remote success id=\(advert.id)")
                if primaryURL != nil || additional != nil {
                    DispatchQueue.main.async {
                        if let idx = self?.adverts.firstIndex(where: { $0.id == advert.id }) {
                            var copy = self!.adverts[idx]
                            if let p = primaryURL { copy.imageStorageURL = p }
                            if let a = additional { copy.imageStorageURLs = a }
                            self?.adverts[idx] = copy
                        }
                        self?.uploadRetries.removeValue(forKey: advert.id)
                    }
                }
            }
        }

        // Re-run background uploader in case this advert added local image paths
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.runBackgroundUploader()
        }
    }

    // Simple background uploader: look for adverts with local image paths but missing storage URLs and attempt upload.
    // Uses a lightweight retry/backoff per advert stored in-memory.
    private var uploadRetries: [UUID: Int] = [:]

    func runBackgroundUploader() {
        // iterate copy to avoid mutation during iteration
        let items = adverts
        for ad in items {
            // if advert already has storage URLs, or has no local image sources, skip
            let hasLocalSource =
                (ad.imageData != nil) || (ad.imageLocalPath != nil)
                || (ad.imageLocalPaths != nil && !(ad.imageLocalPaths!.isEmpty))
            let hasPrimaryURL = (ad.imageStorageURL != nil) || (!hasLocalSource)
            if hasPrimaryURL { continue }

            // If we have local paths (multiple) or a single local path, attempt to read files and upload
            var filesToRead: [String] = []
            if let paths = ad.imageLocalPaths, !paths.isEmpty {
                filesToRead = paths
            } else if let local = ad.imageLocalPath {
                filesToRead = [local]
            }

            if filesToRead.isEmpty { continue }

            // Read all files into Data array (skip files that fail to read)
            var datas: [Data] = []
            for p in filesToRead {
                if let d = try? Data(contentsOf: URL(fileURLWithPath: p)) { datas.append(d) }
            }
            if datas.isEmpty { continue }

            var attempt = uploadRetries[ad.id] ?? 0
            if attempt >= 5 { continue }
            attempt += 1
            uploadRetries[ad.id] = attempt

            // create a copy of advert with imageDatas populated from disk for upload
            var toUpload = ad
            // primary imageData is first entry; additional images go into imageDatas
            toUpload.imageData = datas.first
            if datas.count > 1 { toUpload.imageDatas = Array(datas.dropFirst()) }

            let delay = pow(2.0, Double(attempt - 1))  // exponential backoff: 1,2,4,8...
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                FirebaseManager.shared.createOrUpdateAdvert(toUpload) {
                    [weak self] err, primaryURL, additional in
                    if let err = err {
                        print(
                            "[AdvertManager] background upload error for \(toUpload.id): \(err) (attempt \(attempt))"
                        )
                        // leave retry count to try later
                    } else {
                        print("[AdvertManager] background upload succeeded for \(toUpload.id)")
                        // update local advert with returned URLs if available
                        DispatchQueue.main.async {
                            if let idx = self?.adverts.firstIndex(where: { $0.id == toUpload.id }) {
                                var copy = self!.adverts[idx]
                                if let p = primaryURL { copy.imageStorageURL = p }
                                if let a = additional { copy.imageStorageURLs = a }
                                self?.adverts[idx] = copy
                            }
                            // clear retry counter
                            self?.uploadRetries.removeValue(forKey: toUpload.id)
                        }
                    }
                }
            }
        }
    }

    func delete(_ advert: Advert) {
        adverts.removeAll { $0.id == advert.id }
        print("[AdvertManager] deleting advert id=\(advert.id)")
        FirebaseManager.shared.deleteAdvert(id: advert.id.uuidString) { err in
            if let err = err {
                print("Advert remote delete error: \(err)")
            } else {
                print("[AdvertManager] delete remote success id=\(advert.id)")
            }
        }
    }

    // MARK: - Persistence

    func saveLocalAdverts(_ advertsToSave: [Advert]) {
        do {
            // Strip binary image data before persisting to UserDefaults to avoid exceeding CFPreferences limits
            let sanitized = advertsToSave.map { advert -> Advert in
                var copy = advert
                copy.imageData = nil
                copy.imageDatas = nil
                return copy
            }
            let data = try JSONEncoder().encode(sanitized)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("AdvertManager save error: \(error)")
        }
    }

    func loadLocalAdverts() -> [Advert]? {
        // Attempt to migrate any cached images from Caches/Adverts into Application Support and update saved paths
        let migrated = ImageFileManager.migrateFromCachesIfNeeded()

        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return nil
        }
        do {
            var loaded = try JSONDecoder().decode([Advert].self, from: data)
            // Remap any imageLocalPath(s) from old caches to new paths if migration occurred
            if !migrated.isEmpty {
                for i in 0..<loaded.count {
                    var ad = loaded[i]
                    if let p = ad.imageLocalPath, let new = migrated[p] { ad.imageLocalPath = new }
                    if let ps = ad.imageLocalPaths {
                        var newArr: [String] = []
                        for path in ps { newArr.append(migrated[path] ?? path) }
                        ad.imageLocalPaths = newArr
                    }
                    loaded[i] = ad
                }
            }
            return loaded
        } catch {
            print("AdvertManager load error: \(error)")
            return nil
        }
    }

    private func save() {
        saveLocalAdverts(adverts)
    }

    private func load() {
        if let loadedAdverts = loadLocalAdverts() {
            adverts = loadedAdverts
        } else {
            // Start with empty adverts instead of sample data
            adverts = []
        }
    }

    // MARK: - Clear Data

    func clearAllAdverts() {
        adverts.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("[AdvertManager] All adverts cleared")
    }
}
