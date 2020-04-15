//
//  MapViewController.swift
//  Park Observer
//
//  Created by Regan E. Sarwas on 4/6/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//

import ArcGIS

class MapViewController: ObservableObject {

  weak var mapView: AGSMapView? {
    didSet { hookupMapView() }
  }

  @Published var map = AGSMap()
  @Published var rotation = 0.0 {
    didSet {
      if oldValue != rotation {
        print("Saving new rotation: \(rotation)")
        Defaults.mapRotation.write(rotation)
      }
    }
  }

  //This is not published, but could be to support a scalebar in SwiftUI
  private var scale = 0.0 {
    didSet {
      if oldValue != scale {
        print("Saving new scale: \(scale)")
        Defaults.mapScale.write(scale)
      }
    }
  }

  private var center = CLLocationCoordinate2D() {
    didSet {
      if oldValue.latitude != center.latitude {
        print("Saving new latitude: \(center.latitude)")
        Defaults.mapCenterLat.write(center.latitude)
      }
      if oldValue.longitude != center.longitude {
        print("Saving new longitude: \(center.longitude)")
        Defaults.mapCenterLon.write(center.longitude)
      }
    }
  }

  let locationButtonController = LocationButtonController()

  func hookupMapView() {
    guard let mapView = mapView else {
      print("Error: mapView was set to nil; Can't hook it up to the controller")
      return
    }
    setDefaultMap()
    // If I do not set the mapView's map now, it will be set in the view update which occurs
    // after setting the viewport. Setting the map resets the viewpoint to the map extents
    mapView.map = map
    setDefaultViewport(mapView)
    self.locationButtonController.mapView = mapView
    mapView.releaseHardwareResourcesWhenBackgrounded = true
    observeViewPoint(mapView)
  }

  func setDefaultViewport(_ mapView: AGSMapView) { //, completion: @escaping () -> Void) {
    scale = Defaults.mapScale.readDouble()
    guard scale != 0 else {
      // Not a valid scale, so there are no defaults (i.e. first launch)
      return
    }
    rotation = Defaults.mapRotation.readDouble()
    let latitude = Defaults.mapCenterLat.readDouble()
    let longitude = Defaults.mapCenterLon.readDouble()
    center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    let centerPoint = AGSPoint(clLocationCoordinate2D: center)
    print("Restoring rotation to \(rotation)")
    print("Restoring scale to \(scale)")
    print("Restoring latitude to \(latitude)")
    print("Restoring longitude to \(longitude)")
    mapView.setViewpoint(AGSViewpoint(center: centerPoint, scale: scale, rotation: rotation))
  }

  //MARK: - Map Observing

  private func observeViewPoint(_ mapView: AGSMapView) {
    // We want the rotation as often as possible for a smooth compass display,
    // We do the the scale and center as frequently
    let updateCoalescer = Coalescer(
      dispatchQueue: DispatchQueue.main,
      interval: DispatchTimeInterval.milliseconds(500)) {
        self.scale = mapView.mapScale
        let viewpoint = mapView.currentViewpoint(with: .centerAndScale)
        let point = viewpoint?.targetGeometry as? AGSPoint
        if let center = point?.toCLLocationCoordinate2D() {
          self.center = center
        }
    }
    // Can be called at up to 60hz
    mapView.viewpointChangedHandler = {
      DispatchQueue.main.async {
        self.rotation = mapView.rotation
      }
      updateCoalescer.ping()
    }
  }

  //MARK: - Map Loading

  func setDefaultMap() {
    if let name = Defaults.mapName.readString() {
      loadMap(name: name)
    } else {
      loadMap(name: "esri.Imagery")
    }
  }

  func loadMap(name: String) {
    Defaults.mapName.write(name)
    if name.starts(with: "esri.") {
      loadEsriBasemap(name)
    } else {
      loadLocalTileCache(name)
    }
  }

  private func loadLocalTileCache(_ name: String) {
    // The tile package needs to exist in the document directory of the device or simulator
    // For a device use iTunes File Sharing (enable in the info.plist)
    // For the simulator - breakpoint on the next line, to see what the path is
    // This function does no I/O, so the name is not checked until mapView tries to load the map.
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let url = paths[0]
    let path = url.appendingPathComponent(name)
    let cache = AGSTileCache(fileURL: path)
    let layer = AGSArcGISTiledLayer(tileCache: cache)
    let basemap = AGSBasemap(baseLayer: layer)
    map = AGSMap(basemap: basemap)
  }

  let esriBasemaps: [String: () -> AGSBasemap] = [
    "esri.DarkGrayCanvasVector": AGSBasemap.darkGrayCanvasVector,
    "esri.Imagery": AGSBasemap.imagery,
    "esri.ImageryWithLabels": AGSBasemap.imageryWithLabels,
    "esri.ImageryWithLabelsVector": AGSBasemap.imageryWithLabelsVector,
    "esri.LightGrayCanvas": AGSBasemap.lightGrayCanvas,
    "esri.LightGrayCanvasVector": AGSBasemap.lightGrayCanvasVector,
    "esri.NationalGeographic": AGSBasemap.nationalGeographic,
    "esri.NavigationVector": AGSBasemap.navigationVector,
    "esri.Oceans": AGSBasemap.oceans,
    "esri.OpenStreetMap": AGSBasemap.openStreetMap,
    "esri.Streets": AGSBasemap.streets,
    "esri.StreetsNightVector": AGSBasemap.streetsNightVector,
    "esri.StreetsVector": AGSBasemap.streetsVector,
    "esri.StreetsWithReliefVector": AGSBasemap.streetsWithReliefVector,
    "esri.TerrainWithLabels": AGSBasemap.terrainWithLabels,
    "esri.TerrainWithLabelsVector": AGSBasemap.terrainWithLabelsVector,
    "esri.Topographic": AGSBasemap.topographic,
    "esri.TopographicVector": AGSBasemap.topographicVector,
  ]

  private func loadEsriBasemap(_ name: String) {
    if let basemap = esriBasemaps[name] {
      map = AGSMap(basemap: basemap())
    }
  }

}
