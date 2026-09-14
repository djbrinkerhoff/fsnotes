import Foundation
#if canImport(UIKit)
import UIKit
public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformFontDescriptor = UIFontDescriptor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
public typealias PlatformFontDescriptor = NSFontDescriptor
#endif
