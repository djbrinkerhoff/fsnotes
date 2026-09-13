//
//  ProjectSettings.swift
//  FSNotes
//
//  Created by Oleksandr Hlushchenko on 03.03.2023.
//  Copyright © 2023 Oleksandr Hlushchenko. All rights reserved.
//

import Foundation

public class ProjectSettings: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { return true }
 
    public var sortBy: SortBy = .none
    public var sortDirection: SortDirection = .desc
    public var showInCommon: Bool = true
    public var showInSidebar: Bool = true
    public var showNestedFoldersContent: Bool = true
    public var firstLineAsTitle: Bool?
    public var priority: Int = 0
    public var gitAutoPull: Bool = false
    public var gitOrigin: String?
    public var gitPrivateKey: Data?
    public var gitPublicKey: Data?
    public var gitPrivateKeyPassphrase: String?
    public var notesPreview = [String]()
    public var notesAPI: [String: String]?

    // Craft-style appearance
    public var colorName: String?
    public var iconName: String?
    public var displayModeName: String?

    public var folderColor: FolderColor? {
        get { colorName.flatMap { FolderColor(rawValue: $0) } }
        set { colorName = newValue?.rawValue }
    }

    public var folderIcon: String? {
        get { iconName }
        set { iconName = newValue }
    }

    public var displayMode: NoteListDisplayMode {
        get { displayModeName.flatMap { NoteListDisplayMode(rawValue: $0) } ?? .list }
        set { displayModeName = newValue == .list ? nil : newValue.rawValue }
    }

    public override init() {/*_*/}
    
    public required init(coder aDecoder: NSCoder) {
        if let value = aDecoder.decodeObject(of: NSString.self, forKey: "sortBy") as? String, let sort = SortBy(rawValue: value) {
            sortBy = sort
        }

        if let value =  aDecoder.decodeObject(of: NSString.self, forKey: "sortDirection") as? String, let direction = SortDirection(rawValue: value) {
            sortDirection = direction
        }
        
        showInCommon =  aDecoder.decodeBool(forKey: "showInCommon")
        showInSidebar = aDecoder.decodeBool(forKey: "showInSidebar")
        showNestedFoldersContent = aDecoder.decodeBool(forKey: "showNestedFoldersContent")

        if aDecoder.containsValue(forKey: "firstLineAsTitle") {
            firstLineAsTitle = aDecoder.decodeBool(forKey: "firstLineAsTitle")
        }

        priority = aDecoder.decodeInteger(forKey: "priority")
        gitAutoPull =  aDecoder.decodeBool(forKey: "gitAutoPull")

        if let value = aDecoder.decodeObject(of: NSString.self, forKey: "gitOrigin") as? String {
            gitOrigin = value
        }

        if let value = aDecoder.decodeObject(of: NSData.self, forKey: "gitPrivateKey") as? Data {
            gitPrivateKey = value
        }

        if let value = aDecoder.decodeObject(of: NSData.self, forKey: "gitPublicKey") as? Data {
            gitPublicKey = value
        }

        if let value = aDecoder.decodeObject(of: NSString.self, forKey: "gitPrivateKeyPassphrase") as? String {
            gitPrivateKeyPassphrase = value
        }

        if let value = aDecoder.decodeObject(of: [NSArray.self, NSString.self], forKey: "notesPreview") as? [String] {
            notesPreview = value
        }

        if let value = aDecoder.decodeObject(of: [NSDictionary.self, NSString.self], forKey: "notesAPI") as? [String: String] {
            notesAPI = value
        }

        if let value = aDecoder.decodeObject(of: NSString.self, forKey: "colorName") as? String {
            colorName = value
        }

        if let value = aDecoder.decodeObject(of: NSString.self, forKey: "iconName") as? String {
            iconName = value
        }

        if let value = aDecoder.decodeObject(of: NSString.self, forKey: "displayModeName") as? String {
            displayModeName = value
        }
    }

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(sortBy.rawValue, forKey: "sortBy")
        aCoder.encode(sortDirection.rawValue, forKey: "sortDirection")
        aCoder.encode(showInCommon, forKey: "showInCommon")
        aCoder.encode(showInSidebar, forKey: "showInSidebar")
        aCoder.encode(showNestedFoldersContent, forKey: "showNestedFoldersContent")

        if let firstLineAsTitle = firstLineAsTitle {
            aCoder.encode(firstLineAsTitle, forKey: "firstLineAsTitle")
        }

        aCoder.encode(priority, forKey: "priority")
        aCoder.encode(gitAutoPull, forKey: "gitAutoPull")

        if let gitOrigin = gitOrigin {
            aCoder.encode(gitOrigin, forKey: "gitOrigin")
        }
        
        if let gitPrivateKey = gitPrivateKey {
            aCoder.encode(gitPrivateKey, forKey: "gitPrivateKey")
        }

        if let gitPublicKey = gitPublicKey {
            aCoder.encode(gitPublicKey, forKey: "gitPublicKey")
        }
        
        if let gitPrivateKeyPassphrase = gitPrivateKeyPassphrase {
            aCoder.encode(gitPrivateKeyPassphrase, forKey: "gitPrivateKeyPassphrase")
        }

        aCoder.encode(notesPreview, forKey: "notesPreview")

        if let notesAPI = self.notesAPI {
            aCoder.encode(notesAPI, forKey: "notesAPI")
        }

        if let colorName = colorName {
            aCoder.encode(colorName, forKey: "colorName")
        }

        if let iconName = iconName {
            aCoder.encode(iconName, forKey: "iconName")
        }

        if let displayModeName = displayModeName {
            aCoder.encode(displayModeName, forKey: "displayModeName")
        }
    }

    public func setOrigin(_ origin: String?) {
        if let origin = origin, origin.count > 0 {
            gitOrigin = origin
            return
        }

        gitOrigin = nil
    }

    public func isFirstLineAsTitle() -> Bool {
        if let firstLineAsTitle = firstLineAsTitle {
            return firstLineAsTitle
        }

        return UserDefaultsManagement.firstLineAsTitle
    }
}
