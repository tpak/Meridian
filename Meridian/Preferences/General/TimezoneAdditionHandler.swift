// Copyright © 2015 Abhishek Banthia, © 2026 Chris Tirpak

import Cocoa
import CoreLocation
import CoreLoggerKit
import CoreModelKit

protocol TimezoneAdditionHost: AnyObject {
    var searchField: NSSearchField! { get }
    var placeholderLabel: NSTextField! { get }
    var availableTimezoneTableView: NSTableView! { get }
    var timezonePanel: CustomPanel! { get }
    var timezoneTableView: NSTableView! { get }
    var messageLabel: NSTextField! { get }
    var addTimezoneButton: NSButton! { get }
    var progressIndicator: NSProgressIndicator! { get }
    var addButton: NSButton! { get }
    var searchResultsDataSource: SearchDataSource! { get }

    func refreshTimezoneTableView(_ shouldSelectNewlyInsertedTimezone: Bool)
    func refreshMainTable()
}

private enum SpecialTimezoneNames {
    static let anywhereOnEarth = "Anywhere on Earth"
    static let utc = "UTC"
}

private let maxTimezoneCount = 100
private let maxSearchLength = 50
private let searchDebounceInterval: TimeInterval = 0.5
private let searchScrollThreshold = 6

@MainActor
class TimezoneAdditionHandler: NSObject {
    private weak var host: TimezoneAdditionHost?
    private let dataStore: DataStoring
    private let geocoder: GeocodingServicing

    private var searchTask: Task<Void, Never>?
    private var getTimezoneTask: Task<Void, Never>?
    private var installCleanupTask: Task<Void, Never>?

    private var isActivityInProgress = false {
        didSet {
            guard let host = host else { return }
            if isActivityInProgress {
                host.progressIndicator.startAnimation(nil)
            } else {
                host.progressIndicator.stopAnimation(nil)
            }
            host.availableTimezoneTableView.isEnabled = !isActivityInProgress
            host.addButton.isEnabled = !isActivityInProgress
        }
    }

    init(host: TimezoneAdditionHost,
         dataStore: DataStoring = DataStore.shared(),
         geocoder: GeocodingServicing = MapKitGeocodingService()) {
        self.host = host
        self.dataStore = dataStore
        self.geocoder = geocoder
    }

    // MARK: - Search

    @objc func search() {
        guard validateSearchInput() else {
            searchTask?.cancel()
            resetSearchView()
            return
        }

        searchTask?.cancel()
        showSearchInProgress()

        guard let host = host else { return }
        let searchString = host.searchField.stringValue
        searchTask = Task { @MainActor in
            do {
                let place = try await NetworkManager.geocodeAddress(searchString, geocoder: geocoder)
                handleSearchResults(place)
            } catch {
                handleSearchFailure(error)
            }
        }
    }

    private func validateSearchInput() -> Bool {
        guard let host = host,
              let searchString = host.searchField?.stringValue,
              !searchString.isEmpty,
              searchString.count <= maxSearchLength else {
            return false
        }
        return true
    }

    private func showSearchInProgress() {
        guard let host = host else { return }
        if host.availableTimezoneTableView.isHidden {
            host.availableTimezoneTableView.isHidden = false
        }
        host.placeholderLabel.isHidden = false
        isActivityInProgress = true
        host.placeholderLabel.placeholderString = "Searching for \(host.searchField.stringValue)"
        Logger.debug(host.placeholderLabel.placeholderString ?? "")
    }

    private func handleSearchResults(_ place: GeocodedPlace) {
        guard let host = host else { return }
        let displayName = place.formattedAddress ?? "Unknown"
        let timezoneID = place.timeZone?.identifier ?? ""

        let timezoneData = TimezoneData.make(
            timezoneID: timezoneID,
            name: displayName,
            customLabel: displayName,
            latitude: place.coordinate.latitude,
            longitude: place.coordinate.longitude,
            placeIdentifier: place.regionCode ?? ""
        )
        host.searchResultsDataSource.setFilteredArrayValue([timezoneData])

        findLocalSearchResultsForTimezones()
        prepareUIForPresentingResults()
    }

    private func handleSearchFailure(_ error: Error) {
        guard let host = host else { return }
        findLocalSearchResultsForTimezones()
        if host.searchResultsDataSource.timezoneFilteredArray.isEmpty {
            presentError(error)
            return
        }
        prepareUIForPresentingResults()
    }

    private func findLocalSearchResultsForTimezones() {
        guard let host = host else { return }
        TimezoneSearchService.searchLocalTimezones(host.searchField.stringValue, in: host.searchResultsDataSource)
    }

    private func isOfflineError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.code == NSURLErrorNotConnectedToInternet ||
               nsError.code == NSURLErrorNetworkConnectionLost ||
               nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    private func presentError(_ error: Error) {
        guard let host = host else { return }
        if isOfflineError(error) {
            host.placeholderLabel.placeholderString = PreferencesConstants.noInternetConnectivityError
        } else {
            host.placeholderLabel.placeholderString = PreferencesConstants.tryAgainMessage
        }
        isActivityInProgress = false
    }

    private func prepareUIForPresentingResults() {
        guard let host = host else { return }
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        isActivityInProgress = false
        reloadSearchResults()
    }

    private func reloadSearchResults() {
        guard let host = host else { return }
        if host.searchResultsDataSource.calculateChangesets() {
            Logger.debug("Reloading Search Results")
            host.availableTimezoneTableView.reloadData()
        }
    }

    private func resetSearchView() {
        searchTask?.cancel()

        guard let host = host else { return }
        isActivityInProgress = false
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
    }

    // MARK: - Timezone Fetching

    private func getTimezone(for latitude: Double, and longitude: Double) {
        guard let host = host else { return }

        if host.placeholderLabel.isHidden {
            host.placeholderLabel.isHidden = false
        }

        host.searchField.placeholderString = "Fetching data might take some time!"
        host.placeholderLabel.placeholderString = "Retrieving timezone data"
        host.availableTimezoneTableView.isHidden = true

        getTimezoneTask?.cancel()
        getTimezoneTask = Task { @MainActor in
            do {
                let location = CLLocation(latitude: latitude, longitude: longitude)
                let places = try await geocoder.reverse(location: location)

                guard let place = places.first,
                      let timezone = place.timeZone else {
                    host.placeholderLabel.placeholderString = "No timezone found! Try entering an exact name."
                    host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                                           comment: "Search Field Placeholder")
                    isActivityInProgress = false
                    return
                }

                if host.availableTimezoneTableView.selectedRow >= 0 {
                    installTimezone(timezone)
                }
                updateViewState()
            } catch {
                let nsError = error as NSError
                if nsError.code == NSURLErrorNotConnectedToInternet || nsError.code == NSURLErrorNetworkConnectionLost {
                    host.placeholderLabel.placeholderString = PreferencesConstants.noInternetConnectivityError
                } else {
                    host.placeholderLabel.placeholderString = PreferencesConstants.tryAgainMessage
                }

                isActivityInProgress = false
            }
        }
    }

    private func installTimezone(_ timezone: TimeZone) {
        guard let host = host else { return }
        guard let dataObject = host.searchResultsDataSource.retrieveFilteredResultFromGoogleAPI(host.availableTimezoneTableView.selectedRow) else {
            Logger.debug("Data was unexpectedly nil")
            return
        }

        var filteredAddress = "Error"

        if let address = dataObject.formattedAddress {
            filteredAddress = address.filteredName()
        }

        let timezoneObject = TimezoneData.make(
            timezoneID: timezone.identifier,
            name: filteredAddress,
            customLabel: filteredAddress,
            latitude: dataObject.latitude ?? 0.0,
            longitude: dataObject.longitude ?? 0.0,
            placeIdentifier: dataObject.placeID ?? "",
            nextUpdate: UserDefaultKeys.emptyString
        )

        let operationsObject = TimezoneDataOperations(with: timezoneObject, store: dataStore)
        operationsObject.saveObject()

        Logger.debug("Filtered Address: PlaceName=\(filteredAddress), Timezone=\(timezone.identifier)")
    }

    private func updateViewState() {
        guard let host = host else { return }
        host.searchResultsDataSource.cleanupFilterArray()
        reloadSearchResults()
        host.refreshTimezoneTableView(true)
        host.refreshMainTable()
        host.timezonePanel.close()
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                               comment: "Search Field Placeholder")
        host.availableTimezoneTableView.isHidden = false
        isActivityInProgress = false
    }

    private func showMessage() {
        guard let host = host else { return }
        host.placeholderLabel.placeholderString = PreferencesConstants.noInternetConnectivityError
        isActivityInProgress = false
        host.searchResultsDataSource.cleanupFilterArray()
        reloadSearchResults()
    }

    // MARK: - Add to Favorites

    func addToFavorites() {
        guard let host = host else { return }
        isActivityInProgress = true

        if host.availableTimezoneTableView.selectedRow == -1 {
            host.timezonePanel.contentView?.makeToast(PreferencesConstants.noTimezoneSelectedErrorMessage)
            isActivityInProgress = false
            return
        }

        let selectedTimeZones = dataStore.timezones()
        if selectedTimeZones.count >= maxTimezoneCount {
            host.timezonePanel.contentView?.makeToast(PreferencesConstants.maxTimezonesErrorMessage)
            isActivityInProgress = false
            return
        }

        if host.searchField.stringValue.isEmpty {
            addTimezoneIfSearchStringIsEmpty()
        } else {
            addTimezoneIfSearchStringIsNotEmpty()
        }
    }

    private func addTimezoneIfSearchStringIsEmpty() {
        guard let host = host else { return }
        let currentRowType = host.searchResultsDataSource.placeForRow(host.availableTimezoneTableView.selectedRow)

        switch currentRowType {
        case .timezone:
            cleanupAfterInstallingTimezone()
        default:
            return
        }
    }

    private func addTimezoneIfSearchStringIsNotEmpty() {
        guard let host = host else { return }
        let currentRowType = host.searchResultsDataSource.placeForRow(host.availableTimezoneTableView.selectedRow)

        switch currentRowType {
        case .timezone:
            cleanupAfterInstallingTimezone()
            return
        case .city:
            cleanupAfterInstallingCity()
        }
    }

    private func cleanupAfterInstallingCity() {
        guard let host = host else { return }
        guard let dataObject = host.searchResultsDataSource.retrieveFilteredResultFromGoogleAPI(host.availableTimezoneTableView.selectedRow) else {
            Logger.debug("Data was unexpectedly nil")
            return
        }

        if host.messageLabel.stringValue.isEmpty {
            host.searchField.stringValue = UserDefaultKeys.emptyString

            // If the TimezoneData already has a timezoneID from CLGeocoder, install directly
            if let timezoneID = dataObject.timezoneID, !timezoneID.isEmpty {
                let filteredAddress = (dataObject.formattedAddress ?? "Error").filteredName()

                let timezoneObject = TimezoneData.make(
                    timezoneID: timezoneID,
                    name: filteredAddress,
                    customLabel: filteredAddress,
                    latitude: dataObject.latitude ?? 0.0,
                    longitude: dataObject.longitude ?? 0.0,
                    placeIdentifier: dataObject.placeID ?? "",
                    nextUpdate: UserDefaultKeys.emptyString
                )
                let operationsObject = TimezoneDataOperations(with: timezoneObject, store: dataStore)
                operationsObject.saveObject()

                Logger.debug("Filtered Address: PlaceName=\(filteredAddress), Timezone=\(timezoneID)")
                updateViewState()
            } else {
                // Fall back to reverse geocoding if no timezone ID
                guard let latitude = dataObject.latitude, let longitude = dataObject.longitude else {
                    Logger.debug("Data was unexpectedly nil")
                    return
                }
                getTimezone(for: latitude, and: longitude)
            }
        }
    }

    private func performPostInstallCleanup() {
        guard let host = host else { return }
        host.searchResultsDataSource.cleanupFilterArray()
        host.searchResultsDataSource.timezoneFilteredArray = []
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        host.searchField.stringValue = UserDefaultKeys.emptyString
        reloadSearchResults()
        host.refreshTimezoneTableView(true)
        host.refreshMainTable()
        host.timezonePanel.close()
        host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                               comment: "Search Field Placeholder")
        host.availableTimezoneTableView.isHidden = false
        isActivityInProgress = false
    }

    private func cleanupAfterInstallingTimezone() {
        guard let host = host else { return }
        let data = TimezoneData()

        let currentSelection = host.searchResultsDataSource.retrieveSelectedTimezone(host.availableTimezoneTableView.selectedRow)

        let metaInfo = metadata(for: currentSelection)
        data.timezoneID = metaInfo.0.name

        let cityComponents = metaInfo.0.name.split(separator: "/")
        let defaultLabel = cityComponents.last.map { String($0).replacingOccurrences(of: "_", with: " ") } ?? metaInfo.0.name
        data.setLabel(defaultLabel)
        data.formattedAddress = metaInfo.1.formattedName
        data.selectionType = .timezone
        let shouldBeSystem = metaInfo.0.name == NSTimeZone.system.identifier
        data.isSystemTimezone = shouldBeSystem
        if shouldBeSystem {
            clearStaleSystemTimezoneFlags()
        }

        // Geocode coordinates before saving so sunrise/sunset works immediately
        let timezoneID = metaInfo.0.name
        let store = self.dataStore
        installCleanupTask?.cancel()
        installCleanupTask = Task { @MainActor in
            let components = timezoneID.split(separator: "/")
            if let cityComponent = components.last {
                let cityName = cityComponent.replacingOccurrences(of: "_", with: " ")
                guard let place = try? await NetworkManager.geocodeAddress(cityName, geocoder: self.geocoder) else {
                    Logger.debug("Coordinate backfill skipped for \(cityName)")
                    let operationObject = TimezoneDataOperations(with: data, store: store)
                    operationObject.saveObject()
                    self.performPostInstallCleanup()
                    return
                }
                data.latitude = place.coordinate.latitude
                data.longitude = place.coordinate.longitude
            }

            let operationObject = TimezoneDataOperations(with: data, store: store)
            operationObject.saveObject()
            self.performPostInstallCleanup()
        }
    }

    /// Single-home invariant: when a newly-added row claims to be the system
    /// timezone, clear that flag from any other stored row. Without this, a
    /// row added while the Mac was on a different timezone keeps the flag and
    /// continues lighting up the home indicator forever.
    private func clearStaleSystemTimezoneFlags() {
        let existing = dataStore.timezones()
        var rewritten = existing
        for (idx, blob) in existing.enumerated() {
            guard let model = TimezoneData.customObject(from: blob), model.isSystemTimezone else {
                continue
            }
            model.isSystemTimezone = false
            if let updated = NSKeyedArchiver.secureArchive(with: model) {
                rewritten[idx] = updated
            }
        }
        if rewritten != existing {
            dataStore.setTimezones(rewritten)
        }
    }

}

// MARK: - Close Panel, Filter & Selection

extension TimezoneAdditionHandler {
    func closePanel() {
        guard let host = host else { return }
        host.searchResultsDataSource.cleanupFilterArray()
        host.searchResultsDataSource.timezoneFilteredArray = []
        host.searchField.stringValue = UserDefaultKeys.emptyString
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                               comment: "Search Field Placeholder")

        reloadSearchResults()

        host.timezonePanel.close()
        isActivityInProgress = false
        host.addTimezoneButton.state = .off

        host.availableTimezoneTableView.isHidden = false
    }

    func filterArray() {
        guard let host = host else { return }
        host.searchResultsDataSource.cleanupFilterArray()

        if host.searchField.stringValue.count > maxSearchLength {
            isActivityInProgress = false
            reloadSearchResults()
            host.timezonePanel.contentView?.makeToast(PreferencesConstants.maxCharactersAllowed)
            return
        }

        if host.searchField.stringValue.isEmpty == false {
            searchTask?.cancel()
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            perform(#selector(search), with: nil, afterDelay: searchDebounceInterval)
        } else {
            resetSearchView()
        }

        reloadSearchResults()
    }

    func selectNewlyInsertedTimezone() {
        guard let host = host else { return }
        if host.timezoneTableView.numberOfRows > searchScrollThreshold {
            host.timezoneTableView.scrollRowToVisible(host.timezoneTableView.numberOfRows - 1)
        }

        let indexSet = IndexSet(integer: IndexSet.Element(host.timezoneTableView.numberOfRows - 1))
        host.timezoneTableView.selectRowIndexes(indexSet, byExtendingSelection: false)
    }

    private func metadata(for selection: TimezoneMetadata) -> (NSTimeZone, TimezoneMetadata) {
        if selection.formattedName == SpecialTimezoneNames.anywhereOnEarth {
            return (NSTimeZone(name: "GMT-1200") ?? NSTimeZone.default as NSTimeZone, selection)
        } else if selection.formattedName == SpecialTimezoneNames.utc {
            return (NSTimeZone(name: "GMT") ?? NSTimeZone.default as NSTimeZone, selection)
        } else {
            return (selection.timezone, selection)
        }
    }
}
