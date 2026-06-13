# CoreModelKit

The core data model for Meridian's timezones, persisted in `UserDefaults` as `NSSecureCoding` blobs.

- **`TimezoneData`** — the primary model (`NSObject` / `NSSecureCoding`): timezone ID, coordinates, custom label, favorite flag, system-timezone flag, and per-row format overrides. Encoded to `Data` for storage and decoded back via `TimezoneData.customObject(from:)`.
- **`SearchResult` / `Timezone`** — `Codable` types backing timezone search results.
- **`RelativeDayDisplay`, `DateFormat`, `ResultStatus`** — display/format enums shared with the formatting layer.

Depends on **CoreLoggerKit**.
