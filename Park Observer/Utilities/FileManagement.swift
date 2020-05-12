//
//  FileManagement.swift
//  Park Observer
//
//  Created by Regan E. Sarwas on 5/11/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//

import Foundation

extension String {
  static let surveyDirectory = "Surveys"
  static let surveyExtension = "obssurv"
  static let surveyArchiveExtension = "poz"
  static let surveyProtocolExtension = "obsprot"
  static let tileCacheExtension = "tpk"
}

extension FileManager {

  var documentDirectory: URL {
    urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  var libraryDirectory: URL {
    urls(for: .libraryDirectory, in: .userDomainMask)[0]
  }

  var archiveDirectory: URL {
    return documentDirectory
  }

  var mapDirectory: URL {
    return documentDirectory
  }

  var protocolDirectory: URL {
    return documentDirectory
  }

  var surveyDirectory: URL {
    return libraryDirectory.appendingPathComponent(.surveyDirectory, isDirectory: true)
  }

  var archiveNames: [String] {
    return filenames(in: archiveDirectory, with: .surveyArchiveExtension)
  }

  var mapNames: [String] {
    return filenames(in: mapDirectory, with: .tileCacheExtension)
  }

  var protocolNames: [String] {
    return filenames(in: protocolDirectory, with: .surveyProtocolExtension)
  }

  var surveyNames: [String] {
    return filenames(in: surveyDirectory, with: .surveyExtension)
  }

  func archiveURL(with name: String) -> URL {
    return archiveDirectory.appendingPathComponent(name).appendingPathExtension(
      .surveyArchiveExtension)
  }

  func mapURL(with name: String) -> URL {
    return mapDirectory.appendingPathComponent(name).appendingPathExtension(
      .tileCacheExtension)
  }

  func protocolURL(with name: String) -> URL {
    return protocolDirectory.appendingPathComponent(name).appendingPathExtension(
      .surveyProtocolExtension)
  }

  func surveyURL(with name: String) -> URL {
    return surveyDirectory.appendingPathComponent(name).appendingPathExtension(
      .surveyExtension)
  }

  func deleteArchive(with name: String) throws {
    try removeItem(at: archiveURL(with: name))
  }

  func deleteMap(with name: String) throws {
    try removeItem(at: mapURL(with: name))
  }

  func deleteProtocol(with name: String) throws {
    try removeItem(at: protocolURL(with: name))
  }

  func deleteSurvey(with name: String) throws {
    try removeItem(at: surveyURL(with: name))
  }

  func createSurveyDirectory() throws {
    // Do not fail if surveyDirectory exists (withIntermediateDirectories == true)
    try createDirectory(at: surveyDirectory, withIntermediateDirectories: true, attributes: nil)
  }

  func filenames(in directory: URL, with pathExtension: String) -> [String] {
    // return empty array if any errors are encountered
    if let contents = try? contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [], options: [])
    {
      let matches = contents.filter { $0.pathExtension == pathExtension }
      return matches.map { $0.deletingPathExtension().lastPathComponent }
    } else {
      return []
    }
  }

}
