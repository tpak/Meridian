// Copyright © 2015 Abhishek Banthia

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

@MainActor
class TimezoneAdditionHandler: NSObject {
    private weak var host: TimezoneAdditionHost?
    private let dataStore: DataStoring

    private var searchTask: Task<Void, Never>?

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

    init(host: TimezoneAdditionHost, dataStore: DataStoring = DataStore.shared()) {
        self.host = host
        self.dataStore = dataStore
    }

    // MARK: - Search

    @objc func search() {
        guard let host = host else { return }
        let searchString = host.searchField.stringValue

        if searchString.isEmpty {
            searchTask?.cancel()
            resetSearchView()
            return
        }

        searchTask?.cancel()

        if host.availableTimezoneTableView.isHidden {
            host.availableTimezoneTableView.isHidden = false
        }

        host.placeholderLabel.isHidden = false
        isActivityInProgress = true
        host.placeholderLabel.placeholderString = "Searching for \(searchString)"

        Logger.info(host.placeholderLabel.placeholderString ?? "")

        searchTask = Task { @MainActor in
            do {
                let placemark = try await NetworkManager.geocodeAddress(searchString)

                guard let location = placemark.location else {
                    findLocalSearchResultsForTimezones()
                    let noResults = host.searchResultsDataSource.timezoneFilteredArray.isEmpty
                    host.placeholderLabel.placeholderString = noResults
                        ? "No results! Try entering the exact name." : UserDefaultKeys.emptyString
                    reloadSearchResults()
                    isActivityInProgress = false
                    return
                }

                let name = placemark.formattedAddress
                let timezoneID = placemark.timeZone?.identifier ?? ""

                let totalPackage: [String: Any] = [
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude,
                    UserDefaultKeys.timezoneName: name,
                    UserDefaultKeys.customLabel: name,
                    UserDefaultKeys.timezoneID: timezoneID,
                    UserDefaultKeys.placeIdentifier: placemark.isoCountryCode ?? ""
                ]

                let timezoneData = TimezoneData(with: totalPackage)
                host.searchResultsDataSource.setFilteredArrayValue([timezoneData])

                findLocalSearchResultsForTimezones()
                prepareUIForPresentingResults()
            } catch {
                findLocalSearchResultsForTimezones()
                if host.searchResultsDataSource.timezoneFilteredArray.isEmpty {
                    presentError(error.localizedDescription)
                    return
                }
                prepareUIForPresentingResults()
            }
        }
    }

    private func findLocalSearchResultsForTimezones() {
        guard let host = host else { return }
        TimezoneSearchService.searchLocalTimezones(host.searchField.stringValue, in: host.searchResultsDataSource)
    }

    private func presentError(_ errorMessage: String) {
        guard let host = host else { return }
        if errorMessage == PreferencesConstants.offlineErrorMessage {
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
            Logger.info("Reloading Search Results")
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

        Task { @MainActor in
            do {
                let location = CLLocation(latitude: latitude, longitude: longitude)
                let geocoder = CLGeocoder()
                let placemarks = try await geocoder.reverseGeocodeLocation(location)

                guard let placemark = placemarks.first,
                      let timezone = placemark.timeZone else {
                    host.placeholderLabel.placeholderString = "No timezone found! Try entering an exact name."
                    host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                                           comment: "Search Field Placeholder")
                    isActivityInProgress = false
                    return
                }

                if host.availableTimezoneTableView.selectedRow >= 0 {
                    installTimezone(timezone, for: placemark)
                }
                updateViewState()
            } catch {
                if error.localizedDescription == "The Internet connection appears to be offline." {
                    host.placeholderLabel.placeholderString = PreferencesConstants.noInternetConnectivityError
                } else {
                    host.placeholderLabel.placeholderString = PreferencesConstants.tryAgainMessage
                }

                isActivityInProgress = false
            }
        }
    }

    private func installTimezone(_ timezone: TimeZone, for placemark: CLPlacemark) {
        guard let host = host else { return }
        guard let dataObject = host.searchResultsDataSource.retrieveFilteredResultFromGoogleAPI(host.availableTimezoneTableView.selectedRow) else {
            Logger.info("Data was unexpectedly nil")
            return
        }

        var filteredAddress = "Error"

        if let address = dataObject.formattedAddress {
            filteredAddress = address.filteredName()
        }

        let newTimeZone = [
            UserDefaultKeys.timezoneID: timezone.identifier,
            UserDefaultKeys.timezoneName: filteredAddress,
            UserDefaultKeys.placeIdentifier: dataObject.placeID ?? "",
            "latitude": dataObject.latitude ?? 0.0,
            "longitude": dataObject.longitude ?? 0.0,
            "nextUpdate": UserDefaultKeys.emptyString,
            UserDefaultKeys.customLabel: filteredAddress
        ] as [String: Any]

        let timezoneObject = TimezoneData(with: newTimeZone)

        let operationsObject = TimezoneDataOperations(with: timezoneObject, store: dataStore)
        operationsObject.saveObject()

        Logger.log(object: ["PlaceName": filteredAddress, "Timezone": timezone.identifier], for: "Filtered Address")
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
        if selectedTimeZones.count >= 100 {
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
            Logger.info("Data was unexpectedly nil")
            return
        }

        if host.messageLabel.stringValue.isEmpty {
            host.searchField.stringValue = UserDefaultKeys.emptyString

            // If the TimezoneData already has a timezoneID from CLGeocoder, install directly
            if let timezoneID = dataObject.timezoneID, !timezoneID.isEmpty {
                let filteredAddress = (dataObject.formattedAddress ?? "Error").filteredName()

                let newTimeZone = [
                    UserDefaultKeys.timezoneID: timezoneID,
                    UserDefaultKeys.timezoneName: filteredAddress,
                    UserDefaultKeys.placeIdentifier: dataObject.placeID ?? "",
                    "latitude": dataObject.latitude ?? 0.0,
                    "longitude": dataObject.longitude ?? 0.0,
                    "nextUpdate": UserDefaultKeys.emptyString,
                    UserDefaultKeys.customLabel: filteredAddress
                ] as [String: Any]

                let timezoneObject = TimezoneData(with: newTimeZone)
                let operationsObject = TimezoneDataOperations(with: timezoneObject, store: dataStore)
                operationsObject.saveObject()

                Logger.log(object: ["PlaceName": filteredAddress, "Timezone": timezoneID], for: "Filtered Address")
                updateViewState()
            } else {
                // Fall back to reverse geocoding if no timezone ID
                guard let latitude = dataObject.latitude, let longitude = dataObject.longitude else {
                    Logger.info("Data was unexpectedly nil")
                    return
                }
                getTimezone(for: latitude, and: longitude)
            }
        }
    }

    private func cleanupAfterInstallingTimezone() {
        guard let host = host else { return }
        let data = TimezoneData()
        data.setLabel(UserDefaultKeys.emptyString)

        let currentSelection = host.searchResultsDataSource.retrieveSelectedTimezone(host.availableTimezoneTableView.selectedRow)

        let metaInfo = metadata(for: currentSelection)
        data.timezoneID = metaInfo.0.name
        data.formattedAddress = metaInfo.1.formattedName
        data.selectionType = .timezone
        data.isSystemTimezone = metaInfo.0.name == NSTimeZone.system.identifier

        let operationObject = TimezoneDataOperations(with: data, store: dataStore)
        operationObject.saveObject()

        // Geocode coordinates for sunrise/sunset display
        let timezoneID = metaInfo.0.name
        Task { @MainActor in
            await TimezoneAdditionHandler.backfillCoordinates(for: timezoneID, in: self.dataStore)
        }

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

    private func metadata(for selection: TimezoneMetadata) -> (NSTimeZone, TimezoneMetadata) {
        if selection.formattedName == "Anywhere on Earth" {
            return (NSTimeZone(name: "GMT-1200") ?? NSTimeZone.default as NSTimeZone, selection)
        } else if selection.formattedName == "UTC" {
            return (NSTimeZone(name: "GMT") ?? NSTimeZone.default as NSTimeZone, selection)
        } else {
            return (selection.timezone, selection)
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

        if host.searchField.stringValue.count > 50 {
            isActivityInProgress = false
            reloadSearchResults()
            host.timezonePanel.contentView?.makeToast(PreferencesConstants.maxCharactersAllowed)
            return
        }

        if host.searchField.stringValue.isEmpty == false {
            searchTask?.cancel()
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            perform(#selector(search), with: nil, afterDelay: 0.5)
        } else {
            resetSearchView()
        }

        reloadSearchResults()
    }

    func selectNewlyInsertedTimezone() {
        guard let host = host else { return }
        if host.timezoneTableView.numberOfRows > 6 {
            host.timezoneTableView.scrollRowToVisible(host.timezoneTableView.numberOfRows - 1)
        }

        let indexSet = IndexSet(integer: IndexSet.Element(host.timezoneTableView.numberOfRows - 1))
        host.timezoneTableView.selectRowIndexes(indexSet, byExtendingSelection: false)
    }
}

// MARK: - Coordinate Backfill

extension TimezoneAdditionHandler {
    /// Geocode coordinates for a timezone entry and update the stored data.
    /// Extracts city name from IANA timezone ID (e.g. "America/New_York" → "New York").
    static func backfillCoordinates(for timezoneID: String, in store: DataStoring) async {
        let components = timezoneID.split(separator: "/")
        guard let cityComponent = components.last else { return }
        let cityName = cityComponent.replacingOccurrences(of: "_", with: " ")

        do {
            let placemark = try await NetworkManager.geocodeAddress(cityName)
            guard let location = placemark.location else { return }

            let allTimezones = store.timezones()
            var updated = false
            let newTimezones: [Data] = allTimezones.compactMap { data in
                guard let tz = TimezoneData.customObject(from: data) else { return data }
                guard tz.timezoneID == timezoneID,
                      tz.latitude == nil || tz.longitude == nil else { return data }

                tz.latitude = location.coordinate.latitude
                tz.longitude = location.coordinate.longitude
                updated = true
                return NSKeyedArchiver.clocker_archive(with: tz)
            }

            if updated {
                store.setTimezones(newTimezones)
            }
        } catch {
            Logger.info("Failed to geocode coordinates for \(timezoneID): \(error.localizedDescription)")
        }
    }
}
