//
//  GpsPoint.swift
//  Park Observer
//
//  Created by Regan E. Sarwas on 5/15/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//
//

import CoreData
import CoreLocation  // for CLLocationCoordinate2D
import Foundation

@objc(GpsPoint)
public class GpsPoint: NSManagedObject {

  @NSManaged public var altitude: Double // default = -1
  @NSManaged public var course: Double // default = -1
  @NSManaged public var horizontalAccuracy: Double // default = -1
  @NSManaged public var latitude: NSNumber?
  @NSManaged public var longitude: NSNumber?
  @NSManaged public var speed: Double // default = -1
  @NSManaged public var timestamp: Date?
  @NSManaged public var verticalAccuracy: Double // default = -1
  @NSManaged public var mission: Mission?
  @NSManaged public var missionProperty: MissionProperty?
  @NSManaged public var observation: Observation?

}

typealias GpsPoints = [GpsPoint]

// MARK: - Creation

extension GpsPoint {

  static func new(in context: NSManagedObjectContext) -> GpsPoint {
    return NSEntityDescription.insertNewObject(forEntityName: .entityNameGpsPoint, into: context)
      as! GpsPoint
  }

}

// MARK: - Fetching

extension GpsPoints {

  static var fetchRequest: NSFetchRequest<GpsPoint> {
    return NSFetchRequest<GpsPoint>(entityName: .entityNameGpsPoint)
  }

  static var allOrderByTime: NSFetchRequest<GpsPoint> {
    let request: NSFetchRequest<GpsPoint> = fetchRequest
    let sortOrder = NSSortDescriptor(key: "timestamp", ascending: true)
    request.sortDescriptors = [sortOrder]
    return request
  }

}

// MARK: - Computed Properties

typealias Location = CLLocationCoordinate2D

extension GpsPoint {

  var location: Location? {
    guard let lat = latitude?.doubleValue, let lon = longitude?.doubleValue else {
      return nil
    }
    return Location(latitude: lat, longitude: lon)
  }

}
