//
//  AngleDistanceFormDefinition.swift
//  Park Observer
//
//  Created by Regan Sarwas on 7/28/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//

import SwiftUI  // For Binding

struct AngleDistanceFormDefinition {
  let definition: LocationMethod
  let location: AngleDistanceLocation
  let helper: AngleDistanceHelper

  init(definition: LocationMethod, location: AngleDistanceLocation) {
    self.definition = definition
    self.location = location
    self.helper = AngleDistanceHelper(config: definition, heading: location.direction)
  }

}

//MARK: - Computed Properties

extension AngleDistanceFormDefinition {

  var angle: Binding<Double?> {
    return Binding<Double?>(
      get: {
        let angle = self.location.angle
        let heading = self.location.direction
        let deadAhead = self.definition.deadAhead
        let cw = self.definition.direction == .cw
        return self.helper.userAngle(from: angle, with: heading, as: deadAhead, increasing: cw)
      },
      set: { value in
        if let userAngle = value {
          let heading = self.location.direction
          let deadAhead = self.definition.deadAhead
          let cw = self.definition.direction == .cw
          let angle = self.helper.databaseAngle(
            from: userAngle, with: heading, as: deadAhead, increasing: cw)
          self.location.angle = angle
        }
      })
  }

  //TODO Add warning text when angle not in self.definition.deadAhead +/- 90.0

  var angleCaption: String? {
    let min = String(format: "%.0f", self.definition.deadAhead - 180.0)
    let max = String(format: "%.0f", self.definition.deadAhead + 180.0)
    let deadAhead = String(format: "%.0f", definition.deadAhead)
    let dir = definition.direction.rawValue.uppercased()
    return "Range: \(min)°..\(deadAhead)°(ahead)..\(max)°; Increases \(dir)"
    // For debugging
    //let angle = String(format: "%.0f", location.angle)
    //let direction = String(format: "%.0f", location.direction)
    //return "Range: \(min)°..\(deadAhead)° aka \(direction)°(in front)..\(max)°; Increases \(inc) (DB: \(angle)°)"
  }

  var angleFormat: String {
    "%.0f"
  }

  var angleFormatter: NumberFormatter {
    let formatter = NumberFormatter()
    formatter.minimum = NSNumber(value: self.definition.deadAhead - 180.0)
    formatter.maximum = NSNumber(value: self.definition.deadAhead + 180.0)
    formatter.maximumFractionDigits = 0
    return formatter
  }

  var anglePrefix: String {
    "Angle:"
  }

  var angleSuffix: String? {
    "degrees"
  }

  var distance: Binding<Double?> {
    return Binding<Double?>(
      get: {
        return self.helper.convert(meters: self.location.distance, to: self.definition.units)
      },
      set: { value in
        if let value = value {
          let newValue = self.helper.meters(from: value, in: self.definition.units)
          self.location.distance = newValue
        }
      })
  }

  var distanceCaption: String? {
    "Range: 0..1000"
    // For debugging
    //"Range: 0..1000 (DB:\(self.location.distance) meters)"
  }

  var distanceFormat: String {
    "%.0f"
  }

  var distanceFormatter: NumberFormatter {
    let formatter = NumberFormatter()
    formatter.minimum = 0
    formatter.maximum = 1000
    formatter.maximumFractionDigits = 0
    return formatter
  }

  var distancePlaceholder: String {
    ""
  }

  var distancePrefix: String {
    "Distance:"
  }

  var distanceSuffix: String? {
    definition.units.rawValue
  }

  var footer: String? {
    nil
  }

  var header: String? {
    "Location of feature from observer"
  }

}
