//
//  Copyright (C) 2002-2022   The FreeCol Team
//
//  This file is part of FreeCol.
//
//  FreeCol is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 2 of the License, or
//  (at your option) any later version.
//
//  FreeCol is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with FreeCol.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import FreeColIO

/// Makes resources from URIs, once each: a URI met again gives the
/// resource already made, whatever the key (common/resources/ResourceFactory).
///
/// The kind of resource follows from the URI and the key:
/// "urn:color:" and "urn:font:" URIs; a path ending in a quote is a
/// string; ".faf", ".sza", ".ttf", ".wav", ".video.ogg" and ".ogg" go
/// by their extension; other keys starting "sound." are sounds; the
/// rest are images.
public final class ResourceFactory {

    private var resources: [String: Resource] = [:]

    public init() {}

    /// The resource for a URI, or nil if it can not be made (where Java
    /// logs the failure).
    public func createResource(key: String, cachingKey: String, uri: JavaURI) -> Resource? {
        if let r = resources[uri.string] { return r }
        let pathPart = uri.path ?? ""
        let resource: Resource?
        if uri.scheme == "urn" {
            let ssp = uri.schemeSpecificPart
            if ssp.hasPrefix(ColorResource.scheme) {
                resource = ColorResource(cachingKey: cachingKey, locator: uri)
            } else if ssp.hasPrefix(FontResource.scheme) {
                resource = FontResource(cachingKey: cachingKey, locator: uri)
            } else {
                return nil // Java warns of an unknown urn
            }
        } else if pathPart.hasSuffix("\"") {
            // Java also looks for a quote at or before the last
            // character, which always finds the last one.
            resource = StringResource(cachingKey: cachingKey, locator: uri)
        } else if pathPart.hasSuffix(".faf") {
            resource = FAFileResource(cachingKey: cachingKey, locator: uri)
        } else if pathPart.hasSuffix(".sza") {
            resource = SZAResource(cachingKey: cachingKey, locator: uri)
        } else if pathPart.hasSuffix(".ttf") {
            resource = FontResource(cachingKey: cachingKey, locator: uri)
        } else if pathPart.hasSuffix(".wav") {
            resource = AudioResource(cachingKey: cachingKey, locator: uri)
        } else if pathPart.hasSuffix(".ogg") {
            resource = pathPart.hasSuffix(".video.ogg")
                ? VideoResource(cachingKey: cachingKey, locator: uri)
                : AudioResource(cachingKey: cachingKey, locator: uri)
        } else if key.hasPrefix("sound.") {
            resource = AudioResource(cachingKey: cachingKey, locator: uri)
        } else {
            resource = ImageResource(cachingKey: cachingKey, locator: uri)
        }
        if let resource { resources[uri.string] = resource }
        return resource
    }
}

/// Resources by key, one table per kind (common/resources/ResourceMapping).
///
/// Each kind but strings requires its keys to start with its prefix:
/// "color.", "font.", "animatedfont.", "animation.", "sound.", "video."
/// and "image.".
public final class ResourceMapping {

    public private(set) var colorResources: [String: ColorResource] = [:]
    public private(set) var fontResources: [String: FontResource] = [:]
    public private(set) var stringResources: [String: StringResource] = [:]
    public private(set) var fafResources: [String: FAFileResource] = [:]
    public private(set) var szaResources: [String: SZAResource] = [:]
    public private(set) var audioResources: [String: AudioResource] = [:]
    public private(set) var videoResources: [String: VideoResource] = [:]
    public private(set) var imageResources: [String: ImageResource] = [:]

    public init() {}

    /// Add a resource under a key, if the key has the prefix for its
    /// kind (Java logs a warning for one that does not).
    @discardableResult
    public func add(_ key: String, _ resource: Resource) -> Bool {
        func put<R: Resource>(_ table: inout [String: R], _ prefix: String?) -> Bool {
            if let prefix, !key.hasPrefix(prefix) { return false }
            table[key] = (resource as! R)
            return true
        }
        switch resource {
        case is ColorResource: return put(&colorResources, "color.")
        case is FontResource: return put(&fontResources, "font.")
        case is StringResource: return put(&stringResources, nil)
        case is FAFileResource: return put(&fafResources, "animatedfont.")
        case is SZAResource: return put(&szaResources, "animation.")
        case is AudioResource: return put(&audioResources, "sound.")
        case is VideoResource: return put(&videoResources, "video.")
        case is ImageResource: return put(&imageResources, "image.")
        default: preconditionFailure("Unknown resource \(resource)")
        }
    }

    /// Add the resource of one key under another, looking through the
    /// kinds in Java's order.
    @discardableResult
    public func duplicateResource(_ key: String, _ keyNew: String) -> Bool {
        let found: Resource? = colorResources[key] ?? fontResources[key] ?? stringResources[key]
            ?? fafResources[key] ?? szaResources[key] ?? audioResources[key] ?? videoResources[key]
            ?? imageResources[key]
        guard let found else { return false }
        return add(keyNew, found)
    }

    /// Add another mapping's resources, replacing any here with the
    /// same keys.
    public func addAll(_ other: ResourceMapping?) {
        guard let other else { return }
        colorResources.merge(other.colorResources) { $1 }
        fontResources.merge(other.fontResources) { $1 }
        stringResources.merge(other.stringResources) { $1 }
        fafResources.merge(other.fafResources) { $1 }
        szaResources.merge(other.szaResources) { $1 }
        audioResources.merge(other.audioResources) { $1 }
        videoResources.merge(other.videoResources) { $1 }
        imageResources.merge(other.imageResources) { $1 }
    }

    /// Every resource, by key.
    public var allResources: [String: Resource] {
        var result: [String: Resource] = [:]
        for (k, v) in colorResources { result[k] = v }
        for (k, v) in fontResources { result[k] = v }
        for (k, v) in stringResources { result[k] = v }
        for (k, v) in fafResources { result[k] = v }
        for (k, v) in szaResources { result[k] = v }
        for (k, v) in audioResources { result[k] = v }
        for (k, v) in videoResources { result[k] = v }
        for (k, v) in imageResources { result[k] = v }
        return result
    }

    public var imageKeys: Dictionary<String, ImageResource>.Keys {
        imageResources.keys
    }
}
