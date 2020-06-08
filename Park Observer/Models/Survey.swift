//
//  Survey.swift
//  Park Observer
//
//  Created by Regan E. Sarwas on 5/18/20.
//  Copyright © 2020 Alaska Region GIS Team. All rights reserved.
//

import CoreData

/// A Survey is responsible for all interaction with the database
/// It is imutable (of course the database it manages is not)
class Survey {
  let name: String
  let config: SurveyProtocol
  private(set) var info: SurveyInfo
  let viewContext: NSManagedObjectContext

  private init(name: String, info: SurveyInfo, config: SurveyProtocol, viewContext: NSManagedObjectContext) {
    self.name = name
    self.info = info
    self.config = config
    self.viewContext = viewContext
  }

}

//MARK: - Create a survey

extension Survey {

  enum LoadError: Error {
    case noObjectModel
    case noInfo(error: Error)
    case noDatabase(error: Error)
    case noProtocol(error: Error)
  }

  /// Load a survey async, a results with a survey or error will be returned to the completion handler
  /// This is the primary (only way in production) to get a survey object
  static func load(_ name: String, completionHandler: @escaping (Result<Survey, LoadError>) -> Void)
  {
    DispatchQueue.global(qos: .userInitiated).async {
      var result: Result<Survey, LoadError>
      do {
        let info = try SurveyInfo(fromURL: FileManager.default.surveyInfoURL(with: name))
        do {
          let skipValidation = info.version == 1  // Skip validation on legacy surveys
          let config = try SurveyProtocol(
            fromURL: FileManager.default.surveyProtocolURL(with: name),
            skipValidation: skipValidation)
          if let mom = config.managedObjectModel {
            let url = info.version == 1
              ? FileManager.default.surveyOldDatabaseURL(with: name)
              : FileManager.default.surveyDatabaseURL(with: name)
            let psc = NSPersistentStoreCoordinator(managedObjectModel: mom)
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = psc
            do {
              try psc.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: url, options: nil)
              let survey = Survey(name: name, info: info, config: config, viewContext: context)
              result = .success(survey)
            } catch {
              result = .failure(.noDatabase(error: error))
            }
          } else {
            result = .failure(LoadError.noObjectModel)
          }
        } catch {
          result = .failure(.noProtocol(error: error))
        }
      } catch {
        result = .failure(.noInfo(error: error))
      }
      DispatchQueue.main.async {
        completionHandler(result)
      }
    }
  }

  /// Creates (but does not open) a new survey
  /// It returns the filename of the new survey (may be changed to reflect replacing bad filesystem characters or to avoid a conflict)
  /// Will throw if the file exists, unless conflict is .replace or .keepBoth
  /// May also throw if there are other file system errors;
  /// If it does throw, all intermediate files will be deleted, otherwise the new survey is ready to be loaded
  static func create(
    _ name: String, from protocolFile: String, conflict: ConflictResolution = .fail
  ) throws -> String {
    let newName = try FileManager.default.newSurveyDirectory(
      name.sanitizedFileName, conflict: conflict)
    do {
      let sourceProtocolURL = FileManager.default.protocolURL(with: protocolFile)
      let surveyProtocolURL = FileManager.default.surveyProtocolURL(with: newName)
      try FileManager.default.copyItem(at: sourceProtocolURL, to: surveyProtocolURL)
      let infoURL = FileManager.default.surveyInfoURL(with: newName)
      let info = SurveyInfo(named: name)
      try info.write(to: infoURL)
    } catch {
      try? FileManager.default.deleteSurvey(with: newName)
      throw error
    }
    return newName
  }

}

// MARK: - Instance methods

extension Survey {

  func save() throws {
    if viewContext.hasChanges {
      try viewContext.save()
    }
  }

  func setTitle(_ title: String) {
    //TODO udpate info, and save to disk
  }

  // TODO: make private and call in deinit
  func close() {
    if let psc = viewContext.persistentStoreCoordinator {
      for store in psc.persistentStores {
        try? psc.remove(store)
      }
    }
  }

}

//MARK: - Adding Features

// Called by user actions (UI thread), or CoreLocation updates
// Assume for now that CoreLocation updates happen on the UI thread as they also update the map.

//MARK: - Refresh Map

// Grabs all objects in a freshly opened survey to update the map.
// Loading large surveys takes a few seconds, but it is unclear where the bottleneck is.
// This might work best if called on as a background task to create the UI data structures
// Then update the map on the UI thread.

//MARK: - Export to CSV

extension Survey {

  /// Grabs all objects in a survey database and writes the data to CSV files on a background thread.
  func exportAsCSV(at url: URL, _ completionHandler: @escaping (Error?) -> Void) {
    let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    privateContext.persistentStoreCoordinator = self.viewContext.persistentStoreCoordinator
    privateContext.perform {
      // This background context cannot use any managed objects from another context/thread,
      // and any objects fetched in this context cannot be passed to another context/thread.
      do {
        let files = try self.csvFiles()
        for fileName in files.keys {
          let fileUrl = url.appendingPathComponent(fileName + ".csv")
          if let fileText = files[fileName] {
            try fileText.write(to: fileUrl, atomically: false, encoding: .utf8)
          }
        }
        DispatchQueue.main.async {
          completionHandler(nil)
        }
      } catch {
        DispatchQueue.main.async {
          completionHandler(error)
        }
      }
    }
  }

  func saveToArchive() {
    //TODO: implement
  }

}
