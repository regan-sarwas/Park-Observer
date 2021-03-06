//
//  Observation.swift
//  Park Observer
//
//  Created by Regan E. Sarwas on 5/15/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//
//

/// A swift interface to the objective-c NSManagedObject class in CoreData

import CoreData
import Foundation

@objc(Observation)
public class Observation: NSManagedObject {

  @NSManaged public var adhocLocation: AdhocLocation?
  @NSManaged public var angleDistanceLocation: AngleDistanceLocation?
  @NSManaged public var gpsPoint: GpsPoint?
  @NSManaged public var mission: Mission?

//  Debugging help to see when an observation attribute is read/written
//  public override func value(forKey key: String) -> Any? {
//    print("Observation: getting value for \(key)")
//    let v = super.value(forKey: key)
//    print("Observation: returning \(String(describing: v))")
//    return v
//  }
//
//  public override func setValue(_ value: Any?, forKey key: String) {
//    print("Observation: setting \(key) to \(String(describing: value))")
//    super.setValue(value, forKey: key)
//  }

}

typealias Observations = [Observation]

// MARK: - Creation

extension Observation {

  //TODO: remove as! replace with throw
  static func new(_ feature: Feature, in context: NSManagedObjectContext) -> Observation {
    let entityName = .observationPrefix + feature.name
    return NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
      as! Observation
  }

  static func new(
    _ feature: Feature, mission: Mission, gpsPoint: GpsPoint? = nil,
    adhocLocation: AdhocLocation? = nil, angleDistanceLocation: AngleDistanceLocation? = nil,
    defaults: [String: Any]?, uniqueIdAttribute: Attribute? = nil,
    in context: NSManagedObjectContext
  ) -> Observation {
    let observation = Observation.new(feature, in: context)
    observation.mission = mission
    observation.gpsPoint = gpsPoint
    observation.angleDistanceLocation = angleDistanceLocation
    observation.adhocLocation = adhocLocation
    if let defaults = defaults {
      for key in defaults.keys {
        let dbKey = .attributePrefix + key
        observation.setValue(defaults[key], forKey: dbKey)
      }
    }
    if let attribute = uniqueIdAttribute {
      let key = .attributePrefix + attribute.name
      observation.setValue(Observation.nextId(for: attribute), forKey: key)
    }
    return observation
  }

}

// MARK: - Fetching

extension Observations {

  static func fetchAll(for feature: Feature) -> NSFetchRequest<Observation> {
    let entityName = .observationPrefix + feature.name
    let request: NSFetchRequest<Observation> = NSFetchRequest<Observation>(entityName: entityName)
    return request
  }

  static var fetchAll: NSFetchRequest<Observation> {
    return NSFetchRequest<Observation>(entityName: .entityNameObservation)
  }

  static func fetchFirst(_ feature: Feature, at timestamp: Date, in context: NSManagedObjectContext)
    -> Observation?
  {
    let request = Observations.fetchAll(for: feature)
    request.predicate = NSPredicate.observationFilter(timestamp: timestamp)
    return (try? context.fetch(request))?.first
  }

}

extension NSPredicate {

  static func observationFilter(timestamp: Date) -> NSPredicate {
    let filter =
      "(%@ <= gpsPoint.timestamp AND gpsPoint.timestamp <= %@) OR (%@ <= adhocLocation.timestamp AND adhocLocation.timestamp <= %@)"
    let start = timestamp.addingTimeInterval(-0.001)
    let end = timestamp.addingTimeInterval(+0.001)
    return NSPredicate(
      format: filter, start as CVarArg, end as CVarArg, start as CVarArg, end as CVarArg)
  }

}

// MARK: - Computed Properties

extension Observation {

  var timestamp: Date? {
    return gpsPoint?.timestamp ?? adhocLocation?.timestamp
  }

  func attributes(for feature: Feature) -> [String: Any] {
    var values = [String: Any]()
    for attrib in feature.attributes ?? [] {
      values[attrib.name] = self.value(forKey: .attributePrefix + attrib.name)
    }
    return values
  }

  var locationOfFeature: Location? {
    if let angleDistance = angleDistanceLocation, let location = gpsPoint?.location {
      var adHelper = AngleDistanceHelper(
        config: nil, heading: angleDistance.direction)
      adHelper.absoluteAngle = angleDistance.angle
      adHelper.distanceInMeters = angleDistance.distance
      return adHelper.featureLocationFromUserLocation(location)
    } else {
      if gpsPoint == nil, let location = adhocLocation?.location {
        return location
      } else {
        return gpsPoint?.location
      }
    }
  }

  func requestLocationOfObserver(in context: NSManagedObjectContext? = nil) -> Location? {
    // an observation should always have a gpsPoint or an adhocLocation (mapLocation)
    // If this observation has an adhocLocation, then the observer is
    //   at the gpsPoint with the same time stamp as the adhocLocation
    // If there is no GPS point with a timestamp matching the timestamp of the mapLocation,
    //   Then the observers location is considered unknown.  We might be able to interpolate
    //   between the nearest GPS points, but those might be far off or non-existant, so it is
    //   better to report unknown (via nil) than to guess.
    // If this observation has no adhocLocation, then observer is at the GPS point.
    //   An Observation could have both an adhocLocation and a GPS point.  In this case,
    //   the original observation occurred at the adhocLocation timestamp, and then the location
    //   was corrected at the GPS point timestamp.  There are now two observation locations,
    //   but we will always report the first one.
    // If there is no gpsPoint and no adhocLocation, the the observers location is unknown.
    //   this should be precluded during data input.
    //
    // If an observation has both an adhocLocation and an angleDistanceLocation (should never happen)
    // This function will ignore the angleDistanceLocation
    //
    guard let timestamp = adhocLocation?.timestamp else {
      if let gps = gpsPoint {
        return gps.location
      } else {
        return nil
      }
    }
    let start = timestamp.addingTimeInterval(-0.001)
    let end = timestamp.addingTimeInterval(+0.001)

    let request: NSFetchRequest<GpsPoint> = GpsPoints.fetchRequest
    request.predicate = NSPredicate(
      format: "%@ <= timestamp AND timestamp <= %@", start as CVarArg, end as CVarArg)
    //request.predicate = NSPredicate(format: "timestamp == %@", timestamp as CVarArg)
    var results: GpsPoints?
    if let context = context {
      results = try? context.fetch(request)
    } else {
      // only works when executing in a private context block
      results = try? request.execute()
    }
    guard let gpsPoint = results?.first else {
      return nil
    }
    return gpsPoint.location
  }
}

//MARK: - Unique ID

// See MissionProperty for a discussion of this solution
// Note: Each entity class can have only one unique ID field

extension Observation {

  static private var currentIds = [String: Int32]()

  static func nextId(for attribute: Attribute) -> Int32 {
    let currentId = (currentIds[attribute.name] ?? 0) + 1
    currentIds[attribute.name] = currentId
    return currentId
  }

  static func initializeUniqueId(
    feature: Feature, attribute: Attribute, in context: NSManagedObjectContext
  ) {
    let entityName = .observationPrefix + feature.name
    currentIds[attribute.name] =
      fetchMaxId(entityName: entityName, attribute: attribute, in: context) ?? 0
  }

  static func fetchMaxId(
    entityName: String, attribute: Attribute, in context: NSManagedObjectContext
  ) -> Int32? {
    return MissionProperty.fetchMaxId(for: entityName, attribute: attribute, in: context)
  }

}
