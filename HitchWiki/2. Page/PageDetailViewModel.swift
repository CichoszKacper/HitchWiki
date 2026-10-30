//
//  PageDetailViewModel.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 14/10/2021.
//

import UIKit

class PageDetailViewModel: ViewModel, ViewModelProtocol {    
    
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
    
    /// Builds the page text from the `sections` table: bold headings, and the page title in bold where it first appears.
    private func cleanDescription(page: PageRecord) {
        let bodyFont = UIFont.systemFont(ofSize: 20, weight: .regular)
        let description = NSMutableAttributedString()
        
        for section in page.sections {
            if !section.title.isEmpty {
                let headingSize: CGFloat = section.level <= 2 ? 24 : section.level == 3 ? 22 : 20
                let separator = description.length > 0 ? "\n\n" : ""
                description.append(NSAttributedString(string: separator + section.title + "\n",
                                                      attributes: [.font: UIFont.boldSystemFont(ofSize: headingSize)]))
            }
            if !section.text.isEmpty {
                let separator = description.length > 0 && section.title.isEmpty ? "\n\n" : ""
                description.append(NSAttributedString(string: separator + section.text, attributes: [.font: bodyFont]))
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
