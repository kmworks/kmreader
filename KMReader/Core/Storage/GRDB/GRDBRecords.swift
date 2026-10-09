//
// GRDBRecords.swift
//
//

import Foundation
import GRDB

nonisolated extension KomgaInstance: FetchableRecord, MutablePersistableRecord {
  nonisolated static let databaseTableName = "komga_instances"

  nonisolated enum Columns {
    static let id = Column(CodingKeys.id)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case serverURL = "server_url"
    case username
    case authToken = "auth_token"
    case isAdmin = "is_admin"
    case authMethod = "auth_method"
    case apiKeyId = "api_key_id"
    case protected
    case selectedLibraryIdsRaw = "selected_library_ids_raw"
    case createdAt = "created_at"
    case lastUsedAt = "last_used_at"
    case seriesLastSyncedAt = "series_last_synced_at"
    case booksLastSyncedAt = "books_last_synced_at"
  }
}

nonisolated extension KomgaLibrary: FetchableRecord, MutablePersistableRecord {
  nonisolated static let databaseTableName = "komga_libraries"

  nonisolated enum Columns {
    static let id = Column(CodingKeys.id)
    static let instanceId = Column(CodingKeys.instanceId)
    static let libraryId = Column(CodingKeys.libraryId)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case instanceId = "instance_id"
    case libraryId = "library_id"
    case name
    case createdAt = "created_at"
    case fileSize = "file_size"
    case booksCount = "books_count"
    case seriesCount = "series_count"
    case sidecarsCount = "sidecars_count"
  }
}

nonisolated extension KomgaSeries: FetchableRecord, MutablePersistableRecord {
  nonisolated static let databaseTableName = "komga_series"

  nonisolated enum Columns {
    static let id = Column(CodingKeys.id)
    static let seriesId = Column(CodingKeys.seriesId)
    static let libraryId = Column(CodingKeys.libraryId)
    static let instanceId = Column(CodingKeys.instanceId)
    static let created = Column(CodingKeys.created)
    static let lastModified = Column(CodingKeys.lastModified)
    static let metaTitleSort = Column(CodingKeys.metaTitleSort)
    static let downloadAt = Column(CodingKeys.downloadAt)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case seriesId = "series_id"
    case libraryId = "library_id"
    case instanceId = "instance_id"
    case name
    case url
    case created
    case lastModified = "last_modified"
    case booksCount = "books_count"
    case booksReadCount = "books_read_count"
    case booksUnreadCount = "books_unread_count"
    case booksInProgressCount = "books_in_progress_count"
    case metadataRaw = "metadata_raw"
    case booksMetadataRaw = "books_metadata_raw"
    case metaTitle = "meta_title"
    case metaTitleSort = "meta_title_sort"
    case metaPublisherIndex = "meta_publisher_index"
    case metaAuthorsIndex = "meta_authors_index"
    case metaGenresIndex = "meta_genres_index"
    case metaTagsIndex = "meta_tags_index"
    case metaLanguageIndex = "meta_language_index"
    case isUnavailable = "is_unavailable"
    case oneshot
    case downloadStatusRaw = "download_status_raw"
    case downloadError = "download_error"
    case downloadAt = "download_at"
    case downloadedSize = "downloaded_size"
    case downloadedBooks = "downloaded_books"
    case pendingBooks = "pending_books"
    case offlinePolicyRaw = "offline_policy_raw"
    case offlinePolicyLimit = "offline_policy_limit"
    case collectionIdsRaw = "collection_ids_raw"
  }
}

nonisolated extension KomgaBook: FetchableRecord, MutablePersistableRecord {
  nonisolated static let databaseTableName = "komga_books"

  nonisolated enum Columns {
    static let id = Column(CodingKeys.id)
    static let bookId = Column(CodingKeys.bookId)
    static let seriesId = Column(CodingKeys.seriesId)
    static let libraryId = Column(CodingKeys.libraryId)
    static let instanceId = Column(CodingKeys.instanceId)
    static let created = Column(CodingKeys.created)
    static let lastModified = Column(CodingKeys.lastModified)
    static let metaNumberSort = Column(CodingKeys.metaNumberSort)
    static let metaReleaseDate = Column(CodingKeys.metaReleaseDate)
    static let progressReadDate = Column(CodingKeys.progressReadDate)
    static let downloadStatusRaw = Column(CodingKeys.downloadStatusRaw)
    static let mediaProfile = Column(CodingKeys.mediaProfile)
    static let downloadAt = Column(CodingKeys.downloadAt)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case bookId = "book_id"
    case seriesId = "series_id"
    case libraryId = "library_id"
    case instanceId = "instance_id"
    case name
    case url
    case number
    case created
    case lastModified = "last_modified"
    case sizeBytes = "size_bytes"
    case size
    case mediaRaw = "media_raw"
    case metadataRaw = "metadata_raw"
    case readProgressRaw = "read_progress_raw"
    case mediaPagesCount = "media_pages_count"
    case mediaProfile = "media_profile"
    case metaTitle = "meta_title"
    case metaNumber = "meta_number"
    case metaNumberSort = "meta_number_sort"
    case metaReleaseDate = "meta_release_date"
    case progressPage = "progress_page"
    case progressCompleted = "progress_completed"
    case progressReadDate = "progress_read_date"
    case metaAuthorsIndex = "meta_authors_index"
    case metaTagsIndex = "meta_tags_index"
    case isUnavailable = "is_unavailable"
    case oneshot
    case seriesTitle = "series_title"
    case pagesRaw = "pages_raw"
    case tocRaw = "toc_raw"
    case webPubManifestRaw = "web_pub_manifest_raw"
    case epubProgressionRaw = "epub_progression_raw"
    case downloadStatusRaw = "download_status_raw"
    case downloadError = "download_error"
    case downloadAt = "download_at"
    case downloadedSize = "downloaded_size"
    case readListIdsRaw = "read_list_ids_raw"
    case soloPagesRaw = "isolate_pages_raw"
    case epubPreferencesRaw = "epub_preferences_raw"
  }
}

nonisolated extension KomgaCollection: FetchableRecord, MutablePersistableRecord {
  nonisolated static let databaseTableName = "komga_collections"

  nonisolated enum Columns {
    static let id = Column(CodingKeys.id)
    static let collectionId = Column(CodingKeys.collectionId)
    static let instanceId = Column(CodingKeys.instanceId)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case collectionId = "collection_id"
    case instanceId = "instance_id"
    case name
    case ordered
    case createdDate = "created_date"
    case lastModifiedDate = "last_modified_date"
    case filtered
    case isPinned = "is_pinned"
    case seriesIdsRaw = "series_ids_raw"
  }
}

nonisolated extension KomgaReadList: FetchableRecord, MutablePersistableRecord {
  nonisolated static let databaseTableName = "komga_read_lists"

  nonisolated enum Columns {
    static let id = Column(CodingKeys.id)
    static let readListId = Column(CodingKeys.readListId)
    static let instanceId = Column(CodingKeys.instanceId)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case readListId = "read_list_id"
    case instanceId = "instance_id"
    case name
    case summary
    case ordered
    case createdDate = "created_date"
    case lastModifiedDate = "last_modified_date"
    case filtered
    case isPinned = "is_pinned"
    case bookIdsRaw = "book_ids_raw"
    case downloadStatusRaw = "download_status_raw"
    case downloadError = "download_error"
    case downloadAt = "download_at"
    case downloadedSize = "downloaded_size"
    case downloadedBooks = "downloaded_books"
    case pendingBooks = "pending_books"
    case offlinePolicyRaw = "offline_policy_raw"
    case offlinePolicyLimit = "offline_policy_limit"
  }
}

nonisolated extension CustomFont: FetchableRecord, MutablePersistableRecord {
  nonisolated static let databaseTableName = "custom_fonts"

  enum CodingKeys: String, CodingKey {
    case name
    case path
    case fileName = "file_name"
    case fileSize = "file_size"
    case createdAt = "created_at"
  }
}

nonisolated extension PendingProgress: FetchableRecord, MutablePersistableRecord {
  nonisolated static let databaseTableName = "pending_progress"

  enum CodingKeys: String, CodingKey {
    case id
    case instanceId = "instance_id"
    case bookId = "book_id"
    case page
    case completed
    case createdAt = "created_at"
    case progressionData = "progression_data"
  }
}

nonisolated extension SavedFilter: FetchableRecord, MutablePersistableRecord {
  nonisolated static let databaseTableName = "saved_filters"

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case filterTypeRaw = "filter_type_raw"
    case filterDataJSON = "filter_data_json"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

nonisolated extension EpubThemePreset: FetchableRecord, MutablePersistableRecord {
  nonisolated static let databaseTableName = "epub_theme_presets"

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case preferencesJSON = "preferences_json"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}
