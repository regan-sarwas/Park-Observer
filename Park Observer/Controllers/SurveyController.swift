//
//  SurveyController.swift
//  Park Observer
//
//  Created by Regan E. Sarwas on 6/9/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//

/// This class is responsible for updating state in mapView/CoreData in response to CoreLocation and user input.
/// The single source of truth is the SurveyDB, but this data is effectively duplicated in the mapView.
/// Since I can't think of a simple/efficient way for the mapView and CoreData to work together off of a
/// single datasource, I will update both in tandem through this class. To avoid surprises, this is the only class
/// that should update the entities in CoreData or the mapView's layers/markers.
/// This class should be owned by the SceneDelegate (so it can respond to life cycle events) and will provide
/// various publish properties and callbacks to other views or view controllers. This class owns the mapView, and
/// which is shared with other view controllers like the LocationButtonController.
/// It is the delegate for CoreLocation and mapView touches among others.
/// Some of its many tasks
/// - Has observable state for swiftUI views (not mapView) - i.e. on transect, current survey, current map name, ...
/// - Start/Stop trackLogging; Start/Stop observing
/// - Controls background trackLogging (do not write to UI until in foreground); consider battery usage
/// - Controls GPS point frequency; explore battery savings

import ArcGIS  // For AGSMapView and AGSGeoViewTouchDelegate
import Combine  // For Cancellable
import CoreLocation  // For CLLocationManagerDelegate
import Foundation  // For NSObject (for delegates)
import SwiftUI  // For Alert

class SurveyController: NSObject, ObservableObject {

  let mapView = AGSMapView()

  //TODO: surveyName and mapName should be readonly, but views need to see changes
  @Published var surveyName: String? = nil
  @Published var mapName: String? = nil {
    didSet {
      updateMapReference()
    }
  }

  var isInBackground = false {
    didSet {
      if isInBackground {
        saveState()
        startBackgroundLocations()
      } else {
        drawBackgroundLocations()
      }
    }
  }

  @Published var trackLogging = false {
    didSet {
      if trackLogging {
        startTrackLogging()
        startTotalizer()
      } else {
        stopTrackLogging()
        stopTotalizer()
      }
      updateInfoBanner()
    }
  }

  @Published var observing = false {
    didSet {
      if trackLogging {
        addMissionPropertyAtGps()
      }
      updateInfoBanner()
    }
  }

  @Published var enableBackgroundTrackLogging = false {
    didSet {
      if enableBackgroundTrackLogging {
        locationManager.requestAlwaysAuthorization()
      }
    }
  }

  @Published var slideOutMenuVisible = false {
    didSet {
      if !slideOutMenuVisible {
        slideOutClosedActions()
      }
    }
  }

  @Published var slideOutMenuWidth: CGFloat = 300.0
  @Published var message: Message? = nil
  @Published var featuresLocatableWithTouch = [Feature]()
  @Published var featuresLocatableWithoutTouch = [Feature]()
  @Published var gpsAuthorization = GpsAuthorization.unknown
  @Published var enableSurveyControls = false

  // TouchDelegate properties
  @Published var showingAlert = false

  @Published var alert: Alert? = nil

  @Published var selectedObservation: ObservationPresenter? = nil
  @Published var selectedObservations: [ObservationPresenter]? = nil

  //TODO: do these need to be published"  Can they be computed?
  @Published var showingObservationEditor = false
  @Published var showingObservationSelector = false
  @Published var showMapTouchSelectionSheet = false
  @Published var movingGraphic = false

  // I'm not sure this controller should own these other controllers, but it works
  // better than the other options (owned by various views or SceneDelegate).
  // It also simplifies the SceneDelegate, the View environment, and the Views.
  let locationButtonController: LocationButtonController
  let viewPointController: ViewPointController
  let userSettings = UserSettings()
  let locationManager = CLLocationManager()
  var touchDelegate: MapViewTouchDelegate? = nil

  private var survey: Survey? = nil {
    didSet {
      updateMapReference()
      if let survey = survey {
        featuresLocatableWithoutTouch = survey.config.features.locatableWithoutMapTouch
        featuresLocatableWithTouch = survey.config.features.locatableWithMapTouch
        missionPropertyTemplate = MissionProperties.fetchLast(in: survey.viewContext)
        enableSurveyControls = true
        initializeUniqueIds()
      }
    }
  }

  private var mission: Mission? = nil
  private var missionPropertyTemplate: MissionProperty? = nil
  private var mapReference: MapReference? = nil
  private(set) var defaultMapExtentsSet = false

  //Totalizer support
  @Published var isShowingTotalizer = false
  let totalizer = Totalizer()

  //Banner support
  @Published var isShowingInfoBanner = false
  @Published var infoBannerText: String = ""

  var cancellables = [AnyCancellable]()

  //MARK: - Initialize

  override init() {
    locationButtonController = LocationButtonController(mapView: self.mapView)
    viewPointController = ViewPointController(mapView: self.mapView)
    super.init()
    locationManager.delegate = self
    touchDelegate = MapViewTouchDelegate(surveyController: self)
    self.mapView.touchDelegate = touchDelegate
    let cancellable1 = userSettings.$showTotalizer.sink { [weak self] show in
      self?.isShowingTotalizer = show && (self?.trackLogging ?? false)
    }
    cancellables.append(cancellable1)
    let cancellable2 = userSettings.$showInfoBanner.sink { [weak self] show in
      self?.isShowingInfoBanner = show && !(self?.infoBannerText.isEmpty ?? true)
    }
    cancellables.append(cancellable2)
  }

  //MARK: - Load Map/Survey

  func loadMap(name: String? = nil) {
    defaultMapExtentsSet = false
    let defaultMap = Defaults.mapName.readString()
    guard let name = name ?? mapName ?? defaultMap else {
      print("SurveyController.mapName(name:): No name given")
      // MapView will be empty; user can now choose a map to display
      return
    }
    NSLog("Start load map \(name)")
    if name.starts(with: "Esri ") {
      mapView.map = getEsriBasemap(for: name)
    } else {
      mapView.map = getLocalTileCache(for: name)
    }
    mapView.map?.load(completion: { error in
      if let error = error {
        print("Error in mapView.map.load(): \(error)")
        self.mapName = nil
      } else {
        if name == defaultMap {
          self.viewPointController.restoreState()
          self.defaultMapExtentsSet = true
        } else {
          if self.survey != nil {
            self.mapView.zoomToOverlayExtents()
            self.defaultMapExtentsSet = false
          }
        }
        // location tracking should take precedence over the previous extents.
        self.locationButtonController.restoreState()
        self.mapName = name
        NSLog("Finish load map")
      }
    })
  }

  func loadSurvey(name: String? = nil) {
    unloadCurrentSurvey()
    guard let name = name ?? surveyName ?? Defaults.surveyName.readString() else {
      message = Message.warning("No survey loaded. Use the menu to select a survey.")
      return
    }
    NSLog("Start load survey \(name)")
    Survey.load(name) { (result) in
      NSLog("Finish load survey")
      switch result {
      case .success(let survey):
        self.surveyName = name
        self.survey = survey
        self.startNewMission()  // We need a mission to add observation w/o a tracklog
        NSLog("Start draw survey")
        // Map draw can take several seconds for a large survey. Fortunately, the map layers can
        // be updated on a background thread, and mapView updates the UI appropriately.
        DispatchQueue.global(qos: .userInitiated).async {
          self.mapView.draw(survey, zoomToExtents: !self.defaultMapExtentsSet)
          self.defaultMapExtentsSet = false
          NSLog("Finish draw survey")
        }
        break
      case .failure(let error):
        self.message = Message.error("Error loading survey: \(error)")
        break
      }
    }
  }

  func willDelete(_ file: AppFile) {
    if file.type == .survey && file.name == surveyName {
      unloadCurrentSurvey()
    }
    if file.type == .map && file.name == mapName {
      mapView.map = nil
      self.mapName = nil
    }
  }

  /// Save Survey, Stop TrackLogging, and clear all references to objects owned by the survey
  func unloadCurrentSurvey() {
    trackLogging = false
    enableSurveyControls = false
    featuresLocatableWithoutTouch.removeAll()
    featuresLocatableWithTouch.removeAll()
    mission = nil
    missionPropertyTemplate = nil
    mapReference = nil
    selectedObservation = nil
    selectedObservations = nil
    showingObservationEditor = false
    showingObservationSelector = false
    showMapTouchSelectionSheet = false
    movingGraphic = false
    mapView.removeLayers()
    survey = nil
    surveyName = nil
  }

  private func updateMapReference() {
    if let context = survey?.viewContext, let name = mapName {
      let mapInfo = MapInfo(mapName: name)
      mapReference = MapReference.findOrNew(matching: mapInfo, in: context)
    } else {
      mapReference = nil
    }
  }

  //MARK: - Save/Restore State

  func saveState() {
    // To be called when the app goes into the background
    // If the app is terminated this state can be restored when the app relaunches.
    //print("SurveyController.saveState() called on main thread: \(Thread.isMainThread)")
    saveSurvey()
    Defaults.mapName.write(mapName)
    Defaults.surveyName.write(surveyName)
    locationButtonController.saveState()
    viewPointController.saveState()
    Defaults.slideOutMenuWidth.write(slideOutMenuWidth)
    Defaults.backgroundTracklogging.write(enableBackgroundTrackLogging)
    userSettings.saveState()
  }

  func restoreState() {
    userSettings.restoreState()
    enableBackgroundTrackLogging = Defaults.backgroundTracklogging.readBool()
    slideOutMenuWidth = CGFloat(Defaults.slideOutMenuWidth.readDouble())
    slideOutMenuWidth = slideOutMenuWidth < 10.0 ? 300.0 : slideOutMenuWidth
  }

  func initializeUniqueIds() {
    guard let survey = survey else { return }
    if let attribute = survey.config.mission?.attributes?.uniqueIdAttribute {
      MissionProperty.initializeUniqueId(attribute: attribute, in: survey.viewContext)
    }
    for feature in survey.config.features {
      if let attribute = feature.attributes?.uniqueIdAttribute {
        Observation.initializeUniqueId(
          feature: feature, attribute: attribute, in: survey.viewContext)
      }
    }
  }

  func saveSurvey() {
    guard let survey = survey else { return }
    do {
      try survey.save()
    } catch {
      message = Message.error("Unable to save survey: \(error.localizedDescription)")
    }
  }

  //MARK: - Adding GPS Locations

  private var awaitingAuthorizationForTrackLogging = false
  private var awaitingAuthorizationForMissionProperty = false
  private var awaitingAuthorizationForFeatureAtIndex = -1
  private var awaitingLocationForMissionProperty = false
  private var awaitingLocationForFeatureAtIndex = -1
  private var previousGpsPoint: GpsPoint? = nil
  private var savedLocations = [CLLocation]()
  private var awaitingAuthorizationForMapPoint: AGSPoint? = nil
  private var awaitingLocationForMapPoint: AGSPoint? = nil
  private var awaitingFeatureSelectionForMapPoint: AGSPoint? = nil
  private var awaitingFeatureSelectionForMapPointAndTimeStamp: (AGSPoint, Date)? = nil

  func startNewMission() {
    if let context = self.survey?.viewContext {
      mission = Mission.new(in: context)
    }
  }

  func stopTrackLogging() {
    observing = false
    locationManager.stopUpdatingLocation()
    stopWaitingForLocationEvents()
    startNewMission()  // We need a mission outside of tracklogs for adding observation w/o tracklog
    previousGpsPoint = nil
    saveSurvey()
  }

  func stopWaitingForLocationEvents() {
    awaitingAuthorizationForTrackLogging = false
    awaitingAuthorizationForMissionProperty = false
    awaitingAuthorizationForFeatureAtIndex = -1
    awaitingLocationForMissionProperty = false
    awaitingLocationForFeatureAtIndex = -1
    awaitingAuthorizationForMapPoint = nil
    awaitingLocationForMapPoint = nil
    awaitingFeatureSelectionForMapPoint = nil
    awaitingFeatureSelectionForMapPointAndTimeStamp = nil
  }

  func startTrackLogging() {
    guard self.survey != nil else {
      message = Message.error("No survey selected, or survey is corrupt.")
      return
    }

    //TODO: set minimum distance and accuracy standard based on user prefs
    if gpsAuthorization == .unknown {
      locationManager.requestWhenInUseAuthorization()
      trackLogging = false
      awaitingAuthorizationForTrackLogging = true
      return
    }
    if gpsAuthorization == .denied {
      //TODO: raise alert with option to go to settings.  See Location Button
      message = Message.info("App is not authorized to obtain your location. Enable in setttings.")
      trackLogging = false
      return
    }
    startNewMission()
    locationManager.startUpdatingLocation()
    addMissionPropertyAtGps()
  }

  func addMissionPropertyAtGps() {
    if gpsAuthorization == .denied {
      message = Message.error("App is not authorized to obtain your location. Enable in setttings.")
      return
    }
    if gpsAuthorization == .unknown {
      locationManager.requestWhenInUseAuthorization()
      awaitingAuthorizationForMissionProperty = true
      return
    }
    awaitingLocationForMissionProperty = true
    // Cycle the Location Manager to get the current location
    locationManager.stopUpdatingLocation()
    locationManager.startUpdatingLocation()
    // mission property will be added when we get the next GPS location
  }

  func addObservationAtGps(feature: Feature) {
    print("Adding \(feature.name) at \(feature.allowAngleDistance ? "AngleDistance" : "GPS")")
    if let index = survey?.config.features.firstIndex(where: { $0.name == feature.name }) {
      addObservationAtGps(featureIndex: index)
    }
  }

  //TODO: Move code to addObservationAtGps(feature:) and remove dependence on index
  func addObservationAtGps(featureIndex: Int) {
    if gpsAuthorization == .denied {
      message = Message.error("App is not authorized to obtain your location. Enable in setttings.")
      return
    }
    if gpsAuthorization == .unknown {
      locationManager.requestWhenInUseAuthorization()
      awaitingAuthorizationForFeatureAtIndex = featureIndex
      return
    }
    awaitingLocationForFeatureAtIndex = featureIndex
    // Cycle the Location Manager to get the current location
    locationManager.stopUpdatingLocation()
    locationManager.startUpdatingLocation()
    // feature will be added when we get the next GPS location
  }

  fileprivate func addMissionProperty(
    to survey: Survey, atGps gpsPoint: GpsPoint? = nil, atTouch adhocLocation: AdhocLocation? = nil
  ) {
    guard let mission = mission else {
      message = Message.error("No active tracklog (mission). Can't add MissionProperty.")
      //TODO: Do I need to do any cleanup?
      return
    }
    var defaults: [String: Any]? = nil
    if missionPropertyTemplate == nil {
      defaults = survey.config.mission?.dialog?.defaultValues
    }
    var template: (MissionProperty, [Attribute])? = nil
    if let mp = missionPropertyTemplate, let attrs = survey.config.mission?.attributes {
      template = (mp, attrs)
    }
    let uniqueIdAttribute = survey.config.mission?.attributes?.uniqueIdAttribute

    let missionProperty = MissionProperty.new(
      mission: mission, gpsPoint: gpsPoint, adhocLocation: adhocLocation, observing: observing,
      defaults: defaults, template: template, uniqueIdAttribute: uniqueIdAttribute,
      in: survey.viewContext)
    let graphic = mapView.addMissionProperty(missionProperty)
    //TODO: provide an editing context, or a copy of the attributes, in case the user cancels editing
    //TODO: check survey config to see if we edit the mission properties now
    //TODO: save to the template _after_ the user has "saved" the edits, if showing the editor
    self.missionPropertyTemplate = missionProperty
    // Update the totalizer right away so it can get changes to "observing" right away,
    // and then update again after the user is done editing the attributes for changes in the
    // monitored fields
    totalizer.updateProperties(missionProperty)
    //TODO: update the totalizer _after_ the user has "saved" the edits, if showing the editor

    //FIXME!!
    //TODO: selectedObservation = editableObservation(for: graphic, missionProperty: missionProperty, mode: .new)
    selectedObservation = observationPresenter(for: graphic!)  //, mode: .new)
    showingObservationEditor = true
    slideOutMenuVisible = true
  }

  /// Called by the Core Location Delegate whenever a new (or updated) location is available
  func addGpsLocation(_ location: CLLocation) {
    if !trackLogging {
      // This was a one shot GPS point request, so turn it off before we get more
      locationManager.stopUpdatingLocation()
    }
    guard let survey = self.survey else {
      message = Message.error("No active survey.")
      return
    }
    totalizer.updateLocation(location)
    guard let mission = self.mission else {
      var item = "GPS point"
      if awaitingLocationForFeatureAtIndex >= 0 {
        item = "Observation"
        awaitingLocationForFeatureAtIndex = -1
      }
      if awaitingLocationForMissionProperty {
        item = "Mission Property"
        awaitingLocationForMissionProperty = false
      }
      if awaitingLocationForMapPoint != nil {
        item = "Observation at touch location"
        awaitingLocationForMapPoint = nil
        locationManager.stopUpdatingLocation()
      }
      message = Message.error("No active tracklog. Can't add \(item).")
      return
    }
    var redundant = false
    if let oldPoint = previousGpsPoint {
      if location.timestamp == oldPoint.timestamp! {
        print("New location is redundant")
        redundant = true
        if location.horizontalAccuracy < oldPoint.horizontalAccuracy {
          print("New location is better")
          //TODO: redraw previous location and tracklog segment ?
          oldPoint.initializeWith(mission: mission, location: location)
        }
      }
    }
    var gpsPoint: GpsPoint
    if redundant {
      gpsPoint = previousGpsPoint!
    } else {
      if isInBackground {
        //print("Obtained location \(location) in the background")
        savedLocations.append(location)
        return
      }
      gpsPoint = GpsPoint.new(in: survey.viewContext)
      gpsPoint.initializeWith(mission: mission, location: location)
      mapView.addGpsPoint(gpsPoint)
      if let oldPoint = previousGpsPoint {
        mapView.addTrackLogSegment(from: oldPoint, to: gpsPoint, observing: observing)
      }
      self.previousGpsPoint = gpsPoint
    }

    if let observation = selectedObservation, observation.awaitingGps {
      observation.gpsPoint = gpsPoint
    }
    /*
    if awaitingLocationForMissionProperty {
      //TODO: duplicative of addObservation(at:)
      defer {
        awaitingLocationForMissionProperty = false
      }
      addMissionProperty(to: survey, atGps: gpsPoint)
    }
    if awaitingLocationForFeatureAtIndex >= 0 {
      //TODO: duplicative of addObservation(at:)
      //TODO: switch out index for Feature
      defer {
        awaitingLocationForFeatureAtIndex = -1
      }
      let index = awaitingLocationForFeatureAtIndex
      if index < survey.config.features.count {
        let feature = survey.config.features[index]
        let defaults = feature.dialog?.defaultValues
        let uniqueIdAttribute = feature.attributes?.uniqueIdAttribute
        let observation = Observation.new(
          feature, mission: mission, gpsPoint: gpsPoint, defaults: defaults,
          uniqueIdAttribute: uniqueIdAttribute, in: survey.viewContext)
        //TODO: support angleDistance locations
        let graphic = mapView.addFeature(observation, feature: feature, index: index)

        //FIXME!!
        //TODO: selectedObservation = editableObservation(for: graphic, observation: observation, mode: .new)
        selectedObservation = observationPresenter(for: graphic!) //, mode: .new)
        showingObservationEditor = true
        slideOutMenuVisible = true
      }
    }

    if let mapPoint = awaitingLocationForMapPoint {
      //TODO jump to addObservation - wait for feature name having gpsPoint: gpsPoint
      addObservation(at: mapPoint, gpsPoint: gpsPoint)
    }
 */
  }

  //MARK: - Background Locations

  func startBackgroundLocations() {
    locationManager.allowsBackgroundLocationUpdates =
      trackLogging && self.enableBackgroundTrackLogging && gpsAuthorization == .background
    //print("In background. Locations enabled: \(locationManager.allowsBackgroundLocationUpdates)")
  }

  func drawBackgroundLocations() {
    //print("Drawing \(savedLocations.count) locations collected in the background")
    for location in savedLocations {
      addGpsLocation(location)
    }
    savedLocations.removeAll()
  }

  //MARK: - Adding Map Locations
  func addObservation(at mapPoint: AGSPoint) {

    //Note: GPS Authorization is not required for map touch, so .denied is ok
    print("Adding observation at \(mapPoint.toCLLocationCoordinate2D())")
    if gpsAuthorization == .unknown {
      locationManager.requestWhenInUseAuthorization()
      awaitingAuthorizationForMapPoint = mapPoint
      return
      // function will be called again once authorization is determined
    }

    //TODO: Need a mission, or else we cannot save the gpsPoint we are awaiting
    guard let mission = mission else {
      message = Message.error("No active tracklog (mission). Can't add observation at touch.")
      return
    }
    let observationPresenter = ObservationPresenter(survey: survey, mission: mission)
    selectedObservation = observationPresenter
    observationPresenter.initAsMapTouch()

    var features = survey?.config.features.locatableWithMapTouch.map { $0.name } ?? []

    if gpsAuthorization == .denied {
      features.append(.entityNameMissionProperty)
      observationPresenter.gpsDisabled()
    } else {
      // Cycle the Location Manager to get the current location
      locationManager.stopUpdatingLocation()
      locationManager.startUpdatingLocation()
      //TODO: turn off location updates after getting gpsPoint
      // feature will be added after we get the next suitable GPS location
      awaitingFeatureSelectionForMapPoint = mapPoint
      if features.count > 1 {
        showMapTouchSelectionSheet = true
        //TODO: monitor the setter for showMapTouchSelectionSheet to know if it was canceled
      }
    }
    if features.count == 0 {
      print("No features allow locate by map touch in SurveyController.addObservation(at:)")
      return
    }

    for feature in features {
      print("   Adding \(feature)")
    }
  }

  // TODO: We need to wait until the following concurrent tasks are complete:
  //  1) we have a GpsPoint or a Date (if GPS is not available)
  //     GPS may take some time to reach the desired accuracy
  //  2) the feature name to create (alert for user selection)
  func addObservation(at mapPoint: AGSPoint, gpsPoint: GpsPoint) {
  }

  func addObservation(at mapPoint: AGSPoint, feature: String) {
  }

  func addObservation(at mapPoint: AGSPoint, timestamp: Date) {
  }

  //TODO: Switch out featureName for Feature
  func addObservation(
    at mapPoint: AGSPoint, featureName: String, gpsPoint: GpsPoint?, timestamp: Date?
  ) {
    guard let survey = survey else {
      print("No survey in SurveyController.addObservation(at:)")
      return
    }
    guard let feature = survey.config.features.first(where: { $0.name == featureName })
    else {
      print("No feature for featureName in SurveyController.addObservation(at:)")
      return
    }

    let adhocLocation = AdhocLocation.new(in: survey.viewContext)
    adhocLocation.location = mapPoint.toCLLocationCoordinate2D()
    adhocLocation.timestamp = gpsPoint?.timestamp ?? timestamp ?? Date()
    adhocLocation.map = mapReference

    if featureName == .entityNameMissionProperty {
      addMissionProperty(to: survey, atTouch: adhocLocation)
    } else {
      //TODO: this duplicative of code in SurveyController.addGpsLocation()
      //TODO: replace with try Observation.new(featureName, in: context)
      let observation = Observation.new(feature, in: survey.viewContext)
      observation.adhocLocation = adhocLocation
      observation.mission = mission
      // get the graphic from this call
      //TODO: update id if appropriate
      //TODO: set default values from protocol
      //TODO: figure out a better solution to index
      //mapView.addFeature(observation, feature: feature, index: index)
      //TODO: Add and edit feature attributes in slideout panel)
    }
    // add observation attributes to graphic
    // add graphic to correct layer
    //surveyController.selectedGraphic = graphic
    //surveyController.showingFeatureDetails = true
  }

  //TODO: this could be a mission property
  func viewDidSelectFeature(_ feature: Feature) {
    //TODO: Needs to feed into the addObservation() method
    print("   Selected \(feature.name)")
    if let observation = selectedObservation, observation.awaitingFeature {
      observation.observationClass = .feature(feature)
    }

  }

  func slideOutClosedActions() {
    if showingObservationSelector {
      showingObservationSelector = false
    }
    if showingObservationEditor {
      showingObservationEditor = false
      //TODO:
      // if editing canceled, then delete new objects
      // if saving edits, then save new objects and update graphics
      // if using an editing context or a copy of the attributes, then copy to new object
      // If saving a _new_ missionProperty get missionProperty from ObservationEditor and update totalizer
      //   totalizer.updateProperties(missionProperty)
    }
  }

}

//MARK: - Attribute Form Support

extension SurveyController {

  func observationPresenter(for graphic: AGSGraphic) -> ObservationPresenter {
    return ObservationPresenter.review(survey: survey, graphic: graphic)
  }

  //TODO: Add convenience methods
  //TODO: nearly a duplicate of code above in observationForm(for:)
  //func editableObservation(for graphic: AGSGraphic? = nil, observation: Observation) -> EditableObservation {
  //func editableObservation(for graphic: AGSGraphic? = nil, missionProperty: missionProperty) -> EditableObservation {
  /*
  func editableObservation(
    for graphic: AGSGraphic? = nil, mode: EditableObservation.PresentationMode = .review
  ) -> EditableObservation {

    guard let graphic = graphic else {
      print("No graphic provided to SurveyController.editableObservation(for:)")
      return self.selectedObservation ?? ObservationPresenter()
    }
    guard let name = graphic.graphicsOverlay?.overlayID else {
      print("No name found for graphic's layer in SurveyController.editableObservation(for:)")
      return EditableObservation(graphic: graphic, presentationMode: mode)
    }
    var maybeFeature: Feature? = nil
    var fields: [Attribute]? = nil
    var dialog: Dialog? = nil
    if name == .layerNameMissionProperties {
      fields = survey?.config.mission?.attributes
      dialog = survey?.config.mission?.dialog
    } else {
      for feature in survey?.config.features ?? [Feature]() {
        if feature.name == name {
          maybeFeature = feature
          fields = feature.attributes
          dialog = feature.dialog
        }
      }
    }
    guard let timestamp = graphic.attributes[String.attributeKeyTimestamp] as? Date else {
      print("No timestamp found for graphic in SurveyController.editableObservation(for:)")
      return EditableObservation(
        dialog: dialog, fields: fields, graphic: graphic, name: name, presentationMode: mode)
    }

    var item = EditableObservation(
      dialog: dialog, fields: fields, graphic: graphic, name: name, timestamp: timestamp,
      presentationMode: mode)

    guard let context = survey?.viewContext else {
      print("No coredata context found in SurveyController.editableObservation(for:)")
      return item
    }
    if name == .layerNameMissionProperties {
      item.object = MissionProperties.fetchFirst(at: timestamp, in: context)
    } else {
      if let feature = maybeFeature {
        item.object = Observations.fetchFirst(feature, at: timestamp, in: context)
      }
    }
    return item
  }
*/

}

//TODO: Move to a separate file

//MARK: - Totalizer Support
extension SurveyController {
  var totalizerDefinition: MissionTotalizer? {
    return survey?.config.mission?.totalizer
  }

  func startTotalizer() {
    if let definition = totalizerDefinition {
      totalizer.setup(with: definition)
      isShowingTotalizer = userSettings.showTotalizer
    }
  }

  func stopTotalizer() {
    totalizer.clear()
    isShowingTotalizer = false
  }
}

//MARK: - Banner support
extension SurveyController {
  var hasInfoBannerDefinition: Bool {
    survey?.config.observingMessage != nil || survey?.config.notObservingMessage != nil
  }

  func updateInfoBanner() {
    infoBannerText = {
      if observing {
        return survey?.config.observingMessage ?? ""
      } else {
        if trackLogging {
          return survey?.config.notObservingMessage ?? ""
        } else {
          return ""
        }
      }
    }()
    isShowingInfoBanner = userSettings.showInfoBanner && !infoBannerText.isEmpty
  }
}

//MARK: - Map Loading

extension SurveyController {

  private func getLocalTileCache(for name: String) -> AGSMap? {
    // The tile package needs to exist in the document directory of the device or simulator
    // For a device use iTunes File Sharing (enable in the info.plist)
    // For the simulator - breakpoint on the next line, to see what the path is
    // This function does no I/O, so the name is not checked until mapView tries to load the map.
    let path = FileManager.default.mapURL(with: name)
    let cache = AGSTileCache(fileURL: path)
    let layer = AGSArcGISTiledLayer(tileCache: cache)
    let basemap = AGSBasemap(baseLayer: layer)
    return AGSMap(basemap: basemap)
  }

  private func getEsriBasemap(for name: String) -> AGSMap? {
    guard let basemap = OnlineBaseMaps.esri[name] else {
      return nil
    }
    return AGSMap(basemap: basemap())
  }

}

//MARK: - CoreLocation Manager Delegate

extension SurveyController: CLLocationManagerDelegate {

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    message = Message.warning(error.localizedDescription)
    //TODO: - Clear when GPS is back
  }

  func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    print("Location Manager Did Change Authorization to: \(status.description)")
    switch status {
    case .notDetermined:
      gpsAuthorization = .unknown
      break
    case .authorizedAlways:
      gpsAuthorization = .background
      break
    case .authorizedWhenInUse:
      gpsAuthorization = .foreground
      self.enableBackgroundTrackLogging = false
      break
    default:
      gpsAuthorization = .denied
      self.enableBackgroundTrackLogging = false
      trackLogging = false
      break
    }
    if awaitingAuthorizationForTrackLogging {
      trackLogging = true
      awaitingAuthorizationForTrackLogging = false
    }
    if awaitingAuthorizationForMissionProperty {
      addMissionPropertyAtGps()
      awaitingAuthorizationForMissionProperty = false
    }
    if awaitingAuthorizationForFeatureAtIndex >= 0 {
      addObservationAtGps(featureIndex: awaitingAuthorizationForFeatureAtIndex)
      awaitingAuthorizationForFeatureAtIndex = -1
    }
    if let mapPoint = awaitingAuthorizationForMapPoint {
      addObservation(at: mapPoint)
      awaitingAuthorizationForMapPoint = nil
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    for location in locations {
      //TODO: validate: meets accuracy criteria
      let delta = location.timestamp.distance(to: Date())
      if delta < 1.0 {
        addGpsLocation(location)
      } else {
        print("skipping stale location. Age: \(delta)")
      }
    }
  }

}

// MARK: - CLAuthorizationStatus extension

extension CLAuthorizationStatus: CustomStringConvertible {
  public var description: String {
    switch self {
    case .authorizedAlways: return "Authorized Always"
    case .authorizedWhenInUse: return "Authorized When In Use"
    case .denied: return "Denied"
    case .notDetermined: return "Not Determined"
    case .restricted: return "Restricted"
    @unknown default: return "**Unexpected Enum Value**"
    }
  }
}

enum GpsAuthorization {
  /// Don't bother asking, I know the user doesn't allow GPS Locations.  I will get notified if they change thier mind.
  case denied

  /// Authorized to get location in the foreground and background
  case background

  /// User has not set a location preference,  I should ask.
  case unknown

  /// Only authorized to get location in the foreground
  case foreground
}
