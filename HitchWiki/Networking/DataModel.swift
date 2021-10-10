//
//  DataModel.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 10/10/2021.
//

import Foundation

// MARK: - NetworkManager
struct DataModel: Codable {
    let mediawiki: Mediawiki
}

// MARK: - Mediawiki
struct Mediawiki: Codable {
    let siteinfo: Siteinfo
    let page: [Page]
    let xmlns, xmlnsXsi: String
    let xsiSchemaLocation: String
    let version, xmlLang: String

    enum CodingKeys: String, CodingKey {
        case siteinfo, page
        case xmlns = "_xmlns"
        case xmlnsXsi = "_xmlns:xsi"
        case xsiSchemaLocation = "_xsi:schemaLocation"
        case version = "_version"
        case xmlLang = "_xml:lang"
    }
}

// MARK: - Page
struct Page: Codable {
    let title, ns, id: String
    let revision: Revision
    let redirect: Redirect?
    let restrictions: String?
}

// MARK: - Redirect
struct Redirect: Codable {
    let title: String

    enum CodingKeys: String, CodingKey {
        case title = "_title"
    }
}

// MARK: - Revision
struct Revision: Codable {
    let id: String
    let parentid: String?
    let contributor: Contributor
    let model: Model
    let format: Format
    let text: Text
    let sha1: String
    let minor: String?
    let comment: String?
}

// MARK: - Contributor
struct Contributor: Codable {
    let username, id, ip: String?
}

enum Format: String, Codable {
    case textCSS = "text/css"
    case textJavascript = "text/javascript"
    case textXWiki = "text/x-wiki"
}

enum Model: String, Codable {
    case css = "css"
    case javascript = "javascript"
    case wikitext = "wikitext"
}

// MARK: - Text
struct Text: Codable {
    let xmlSpace: XMLSpace
    let bytes: String
    let text: String?

    enum CodingKeys: String, CodingKey {
        case xmlSpace = "_xml:space"
        case bytes = "_bytes"
        case text = "__text"
    }
}

enum XMLSpace: String, Codable {
    case preserve = "preserve"
}

// MARK: - Siteinfo
struct Siteinfo: Codable {
    let sitename, dbname: String
    let base: String
    let generator: String
    let siteinfoCase: Case
    let namespaces: Namespaces

    enum CodingKeys: String, CodingKey {
        case sitename, dbname, base, generator
        case siteinfoCase = "case"
        case namespaces
    }
}

// MARK: - Namespaces
struct Namespaces: Codable {
    let namespace: [Namespace]
}

// MARK: - Namespace
struct Namespace: Codable {
    let key: String
    let namespaceCase: Case
    let text: String?

    enum CodingKeys: String, CodingKey {
        case key = "_key"
        case namespaceCase = "_case"
        case text = "__text"
    }
}

enum Case: String, Codable {
    case firstLetter = "first-letter"
}
