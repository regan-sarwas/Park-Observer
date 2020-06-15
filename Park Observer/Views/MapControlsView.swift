//
//  MapControlsView.swift
//  Park Observer
//
//  Created by Regan E. Sarwas on 4/9/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//

import SwiftUI

struct MapControlsView: View {
  @EnvironmentObject var locationButtonController: LocationButtonController
  @EnvironmentObject var viewPointController: ViewPointController
  @Environment(\.darkMap) var darkMap


  var body: some View {
    print("MapControlsView: rotation = \(viewPointController.rotation)")
    return HStack {
      ScalebarView()
        .frame(width: 200.0, height: 36)
      Spacer()
      if viewPointController.rotation != 0 {
        Button(
          action: {
            //withAnimation(Animation.easeOut(duration: 0.5).delay(0.5)) {
              self.viewPointController.rotation = 0.0
            //}
        }, label: {
          CompassView(rotation: -1 * viewPointController.rotation, darkMode: !darkMap)
        }
        )
        .frame(width: 44, height: 44)
        //.transition(AnyTransition.scale.combined(with:.opacity))
      }
      LocationButtonView(controller: locationButtonController)
    }
  }

}

struct MapDashboardView_Previews: PreviewProvider {
  static var previews: some View {
    MapControlsView()
  }
}
