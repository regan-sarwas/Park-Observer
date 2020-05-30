//
//  LicenseManager.swift
//  Park Observer
//
//  Created by Regan E. Sarwas on 4/7/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//

import ArcGIS

extension String {
  static let licenseKey = "runtimelite,1000,rud9696418117,none,RP5X0H4AH56JXH46C065"
}

enum LicenseManager {

  static func licenseArcGISRuntime() -> Bool {
    // License key is free for "runtime lite"
    // Available on dashboard of Esri developer site
    do {
      let result = try AGSArcGISRuntimeEnvironment.setLicenseKey(.licenseKey)
      print("ArcGIS Runtime license request result: \(result.licenseStatus)")
      return result.licenseStatus == .valid
    } catch {
      // Do not throw or abort.
      // Without license app will run with a "Developer Mode" watermark on the map view
      let nserror = error as NSError
      print("Error licensing ArcGIS Runtime: \(nserror), \(nserror.userInfo)")
      return false
    }
  }

}

extension AGSLicenseStatus: CustomStringConvertible {

  public var description: String {
    switch self {
    case .invalid: return "License is invalid"
    case .expired: return "License has expired"
    case .loginRequired: return "Login required (30 day limit for named user)"
    case .valid: return "License is valid"
    @unknown default: return "** Unexpected/Unknown Status **"
    }
  }

}
