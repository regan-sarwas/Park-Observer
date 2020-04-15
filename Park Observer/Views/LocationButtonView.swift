//
//  LocationButtonView.swift
//  Park Observer
//
//  Created by Regan E. Sarwas on 4/10/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//

import ArcGIS
import SwiftUI

struct LocationButtonView: View {
  @ObservedObject var controller: LocationButtonController

  @State private var showingAlert = false

  var body: some View {
    Button(action: {
      self.showingAlert = self.controller.authorized == .no
      self.controller.toggle()
    }) {
      Image(systemName: getImageName())
    }
      .padding()
      .background(Color(.systemBackground))
      .clipShape(Circle())
      //TODO: change foreground color to disabled if locationAuthorized is nil or false
      //TODO: get background from environment (whiteish for dark maps, blackish for light maps)
      //TODO: make background slightly transparent, make border less transparent
      //TODO: system images are like fonts, experiment with size and weight
      //TODO: coordinate look with CompassView
      .alert(isPresented: $showingAlert) {
        Alert(
          title: Text("Location Services Disabled"),
          message: Text(
            "Your location cannot be shown. Use Settings to enable location services."),
          dismissButton: .default(Text("Got it!")))
        //TODO: provide a primary (cancel) and secondary (settings) buttons
      }
  }

  private func getImageName() -> String {
    if controller.showLocation {
      switch controller.autoPanMode {
      case .off:
        return "location"
      case .compassNavigation:
        return "location.circle"
      case .navigation:
        return "location.north.line.fill"
      case .recenter:
        return "location.fill"
      @unknown default:
        print("Error: Unexpected enum value in AGSLocationDisplayAutoPanMode")
        return "exclamationmark.octagon.fill"
      }
    } else {
      return "location.slash"
    }
  }

}

struct LocationButtonView_Previews: PreviewProvider {
  static var previews: some View {
    LocationButtonView(controller: LocationButtonController())
  }
}
