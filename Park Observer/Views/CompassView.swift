//
//  CompassView.swift
//  Park Observer
//
//  Created by Regan E. Sarwas on 4/8/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//

import SwiftUI

struct CompassView: View {
  @Binding var rotation: Double

  @Environment(\.darkMap) var darkMap

  // TODO: fade out (and remove from view?) after rotation is zero

  var body: some View {
    Button(action: { self.rotation = 0.0 }) {
      GeometryReader { geometry in
        ZStack {
          Triangle()
            .fill(Color(.red))
            .frame(width: geometry.size.width * 0.2, height: geometry.size.height * 0.34)
            .offset(x: 0.0, y: -0.17 * geometry.size.height)
          Triangle()
            .frame(width: geometry.size.width * 0.2, height: geometry.size.height * 0.34)
            .offset(x: 0.0, y: -0.17 * geometry.size.height)
            .rotationEffect(Angle(degrees: 180.0))
        }
      }
        .frame(width: 44, height: 44)
        .foregroundColor(Color(darkMap ? .black : .white))
        .background(Color(darkMap ? .white : .black).opacity(0.65))
        .clipShape(Circle())
        .overlay(Circle().stroke(Color(darkMap ? .white : .black), lineWidth: 3))
        .rotationEffect(Angle(degrees: -rotation))
    }
      .buttonStyle(PlainButtonStyle())
  }
}

struct Triangle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()

    let apex = rect.minX + (rect.maxX - rect.minX) / 2.0
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: apex, y: rect.minY))

    return path
  }
}

struct CompassView_Previews: PreviewProvider {
  static var previews: some View {
    CompassView(rotation: .constant(15.0))
  }
}
