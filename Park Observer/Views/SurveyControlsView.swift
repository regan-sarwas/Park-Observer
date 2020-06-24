//
//  SurveyControlsView.swift
//  Park Observer
//
//  Created by Regan Sarwas on 6/16/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//

import SwiftUI

struct SurveyControlsView: View {
  @EnvironmentObject var surveyController: SurveyController
  @EnvironmentObject var userSettings: UserSettings

  var body: some View {
    HStack(alignment: .bottom) {
      HStack {
        Button(action: {
          self.surveyController.slideOutMenuVisible.toggle()
        }) {
          Image(systemName: "slider.horizontal.3").font(.title)
        }
        .mapButton(darkMode: userSettings.darkMapControls)

        Spacer()

        Button(action: {
          self.surveyController.tracklogging.toggle()
        }) {
          Image(systemName: surveyController.tracklogging ? "stop.fill" : "play.fill").font(
            .headline)
        }
        .mapButton(darkMode: userSettings.darkMapControls)

        Button(action: {
          self.surveyController.observing.toggle()
        }) {
          Image(systemName: surveyController.observing ? "stop.fill" : "play.fill").font(.headline)
        }
        .disabled(!self.surveyController.tracklogging)
        .mapButton(darkMode: userSettings.darkMapControls)

        Button(action: {
          self.surveyController.addMissionPropertyAtGps()
        }) {
          Image(systemName: "cloud.sun.rain").font(.headline)
        }
        .mapButton(darkMode: userSettings.darkMapControls)
      }
      VStack {
        ForEach(0..<self.surveyController.featureNames.count, id: \.self) { index in
          Button(action: {
            self.surveyController.addObservationAtGps(featureIndex: index)
          }) {
            ZStack(alignment: .bottomTrailing) {
              Image(systemName: "plus").font(.largeTitle)
              Text("\(String(self.surveyController.featureNames[index].prefix(1)))")
                .font(.caption).bold()
                //TODO: Make sure this offset works in all cases + dynamic font sizes
                //  maybe best to fix the font size for both "plus" and feature code
                .offset(x: -1, y: 4.0)
            }
          }
          .mapButton(darkMode: self.userSettings.darkMapControls)
        }
      }
    }
  }

}

struct SurveyControlsView_Previews: PreviewProvider {
  static var previews: some View {
    SurveyControlsView()
  }
}
