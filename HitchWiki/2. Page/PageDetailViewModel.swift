//
//  PageDetailViewModel.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 14/10/2021.
//

import UIKit

class PageDetailViewModel: ViewModel, ViewModelProtocol {    
    
    /// Links to other Hitchwiki pages use this app-only scheme, e.g. hitchwiki-page:Krak%C3%B3w,
    /// so the page text view can tell them apart from websites.
    static let pageLinkScheme = "hitchwiki-page"
    
    static func link(toPage title: String) -> URL? {
        var components = URLComponents()
        components.scheme = self.pageLinkScheme
        components.path = title
        return components.url
    }
    
    static func pageTitle(fromLink url: URL) -> String? {
        guard url.scheme == self.pageLinkScheme else {
            return nil
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.path
    }
    
    var page: PageRecord?
    var infoboxValuesArray: [String]?
    var updatedInfoboxValuesArray: [String]?
    var newDictionary: [String:[String:Bool]] = [:]
    var pageDescriptionAttributedString: NSAttributedString?
    
    var stringToBeCalled: String?
    var labelToBeCalled: UILabel?
    /// Title of the page to open when the clickable infobox value is tapped.
    var pageToBeCalled: String?
    
    private let database = HitchwikiDatabase.shared
    
    // MARK: - Updates
    var update: ((PageDetailViewModel.UpdateType) -> Void)?
    enum UpdateType {
        case page
    }
    
    var error: ((PageDetailViewModel.ErrorType) -> Void)?
    enum ErrorType {
        
    }

    func passPage(title: String) {
        do {
            guard let page = try self.database?.page(titled: title) else {
                return
            }
            self.page = page
            if !page.infobox.isEmpty {
                self.cleanInfobox(page: page)
            }
            self.cleanDescription(page: page)
        } catch {
            // TODO: Alert once the Alert Manager is set up
            print("\(error)")
        }
    }
    
    /// Infobox values now come ready from the `infobox_fields` table.
    private func cleanInfobox(page: PageRecord) {
        self.infoboxValuesArray = ["country","language","capital","pop","currency"]
        self.updatedInfoboxValuesArray = self.infoboxValuesArray?.map { $0 == "pop" ? "Population" : $0.capitalized }
        
        for (key, value) in page.infobox {
            guard !value.isEmpty, let index = self.infoboxValuesArray?.firstIndex(of: key.lowercased()),
                  let displayKey = self.updatedInfoboxValuesArray?[index] else {
                continue
            }
            self.newDictionary.updateValue([value: self.checkIfClickable(string: value)], forKey: displayKey)
        }
    }
    
    private func checkIfClickable(string: String) -> Bool {
        (try? self.database?.resolveTitle(string)) != nil
    }
    
    /// Builds the page text from the `sections` table: bold headings, blue tappable links,
    /// and the page title in bold where it first appears.
    private func cleanDescription(page: PageRecord) {
        let bodyFont = UIFont.systemFont(ofSize: 20, weight: .regular)
        let description = NSMutableAttributedString()
        
        /// Appends `separator + text` and marks the links, whose ranges are relative to `text`.
        func append(_ text: String, separator: String, font: UIFont, links: [PageLink]) {
            let start = description.length + (separator as NSString).length
            description.append(NSAttributedString(string: separator + text, attributes: [.font: font, .foregroundColor: UIColor.label]))
            for link in links {
                let range = NSRange(location: start + link.range.location, length: link.range.length)
                guard NSMaxRange(range) <= description.length else {
                    continue
                }
                switch link.destination {
                case .page(let title):
                    if let url = Self.link(toPage: title) {
                        description.addAttribute(.link, value: url, range: range)
                    }
                case .url(let url):
                    description.addAttribute(.link, value: url, range: range)
                }
            }
        }
        
        for section in page.sections {
            if !section.title.isEmpty {
                let headingSize: CGFloat = section.level <= 2 ? 24 : section.level == 3 ? 22 : 20
                append(section.title, separator: description.length > 0 ? "\n\n" : "",
                       font: UIFont.boldSystemFont(ofSize: headingSize), links: section.titleLinks)
                description.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont, .foregroundColor: UIColor.label]))
            }
            if !section.text.isEmpty {
                append(section.text, separator: description.length > 0 && section.title.isEmpty ? "\n\n" : "",
                       font: bodyFont, links: section.links)
            }
        }
        
        // Make the title in text bold, like on the wiki
        let titleRange = description.mutableString.range(of: page.title)
        if titleRange.location != NSNotFound {
            description.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: bodyFont.pointSize), range: titleRange)
        }
        self.pageDescriptionAttributedString = description
    }
    
    public func checkIfShouldMakeClickable(value: Bool, string: String) -> Bool {
        if value && self.page?.title.lowercased() != string.lowercased() {
            return true
        } else {
            return false
        }
    }
    
    private func setUpDataForClickableLabel(string: String, label: UILabel) {
        self.stringToBeCalled = string
        self.labelToBeCalled = label
        self.pageToBeCalled = try? self.database?.resolveTitle(string)
    }
    
    public func addTapGestureToPartOfString(label: UILabel, stringToBeCalled: String) {
        self.setUpDataForClickableLabel(string: stringToBeCalled, label: label)
        let tapGesture = UITapGestureRecognizer.init(target: self, action: #selector(tappedOnLabel(_:)))
        label.lineBreakMode = .byWordWrapping
        label.isUserInteractionEnabled = true
        tapGesture.numberOfTouchesRequired = 1
        label.addGestureRecognizer(tapGesture)
    }
    
    @objc func tappedOnLabel(_ gesture: UITapGestureRecognizer) {
        guard let label = self.labelToBeCalled,
              let stringToBeCalled = self.stringToBeCalled,
              let pageTitle = self.pageToBeCalled else {
            return
        }
        
        if gesture.didTapAttributedString(stringToBeCalled, in: label) {
            let pageDetailViewController = PageDetailViewController(viewModel: PageDetailViewModel())
            pageDetailViewController.populatePage(title: pageTitle)
            pageDetailViewController.modalPresentationStyle = .fullScreen
            UIApplication.topViewController()?.navigationController?.pushViewController(pageDetailViewController, animated: true)
        }
    }
}
