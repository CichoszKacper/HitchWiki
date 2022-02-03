//
//  PageDetailViewModel.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 14/10/2021.
//

import UIKit

class PageDetailViewModel: ViewModel, ViewModelProtocol {    
    
    var pages: [Page]?
    var page: Page?
    private var infoboxValuesArray: [String]?
    private var updatedInfoboxValuesArray: [String]?
    var descriptionClickableValuesArray: [String]?
    var newDictionary: [String:[String:Bool]] = [:]
    var pageDescriptionAttributedString: NSAttributedString?
    
    var stringToBeCalled: String?
    var labelToBeCalled: UILabel?
    var pageToBeCalled: Page?
    let regexSquareBrackets = "\\[\\[((.*?)\\]\\])"
    
    // MARK: - Updates
    var update: ((PageDetailViewModel.UpdateType) -> Void)?
    enum UpdateType {
        case page
    }
    
    var error: ((PageDetailViewModel.ErrorType) -> Void)?
    enum ErrorType {
        
    }

    // MARK: - Public Methods
    func passPage(page: Page, allPages: [Page]) {
        self.page = page
        self.pages = allPages
        guard let description = page.revision.text.text else {
            return
        }

        if description.lowercased().contains("{{infobox") {
            self.cleanInfobox(description: description)
        }

        self.cleanDescription(description: description, page: page)
    }
    
    public func loadData() {
        NetworkManager().readLocalData(forName: "hitchwiki") { [weak self] result in
            switch result {
            case .success(let pagesToDisplay):
                self?.pages = pagesToDisplay
            case .failure(let error):
                // TODO: Alert once the Alert Manager is set up
                print("\(error)")
            }
        }
    }
    
    public func addTapGestureToPartOfString(label: UILabel, stringToBeCalled: String) {
        self.setUpDataForClickableLabel(string: stringToBeCalled, label: label)
        let tapGesture = UITapGestureRecognizer.init(target: self, action: #selector(tappedOnLabel(_:)))
        label.lineBreakMode = .byWordWrapping
        label.isUserInteractionEnabled = true
        tapGesture.numberOfTouchesRequired = 1
        label.addGestureRecognizer(tapGesture)
    }
    
    public func interactWithURL(pageName: String) -> Bool {
        guard let allPages = self.pages,
              let pageNameDecoded = pageName.removingPercentEncoding else {
                  return false
              }
        var shouldRedirect = false
        var correctPageName = self.removeBracketsFromHyperlinks(pageNameDecoded: pageNameDecoded)
        if self.checkIfClickable(string: correctPageName) {
            self.pages?.forEach({ page in
                if page.title.lowercased() == correctPageName.lowercased() {
                    shouldRedirect = ((page.redirect?.title.isEmpty) == nil)
                    if shouldRedirect {
                        ActionManager().pushViewController(page: page, allPages: allPages)
                    } else {
                        correctPageName = page.redirect!.title
                    }
                }
            })
            if !shouldRedirect {
                self.pages?.forEach({ page in
                    if page.title.lowercased() == correctPageName.lowercased() {
                        ActionManager().pushViewController(page: page, allPages: allPages)
                    }
                })
            }
            return true
        }
        // TODO: Create a default view saying that the page for this location is not set up yet
        return true
    }
    
    // MARK: - Private Methods
    private func cleanInfobox(description: String) {
        var finalDescription = description
        if description.contains("IsIn|Romania") {
            if let startingIndexToRemove = description.firstIndex(of: "{"),
               let endingIndexToRemove = description.firstIndex(of: "}") {
                finalDescription.removeSubrange(startingIndexToRemove...endingIndexToRemove)
                finalDescription.removeFirst()
            }
        }
        guard let startingIndex = finalDescription.firstIndex(of: "{"), let endingIndex = finalDescription.firstIndex(of: "}") else {
            return
        }

        let infoboxDescription = finalDescription[startingIndex...endingIndex]
        let rows = infoboxDescription.dropFirst().dropLast().split(separator: "|")
        let infoboxDictionary = rows.dropFirst().reduce(into: [String:String]()) {
            guard let index = $1.firstIndex(of: "=") else {
                return
            }
            
            let key = String($1[$1.startIndex..<index]).trimmingCharacters(in: .whitespaces)
            let value = String($1[$1.index(after: index)..<$1.endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            $0[key] = value
        }
        
        self.infoboxValuesArray = ["country","language","capital","pop","currency"]
        self.updatedInfoboxValuesArray = self.infoboxValuesArray
        for (key,value) in infoboxDictionary {
            if let infoboxValuesArray = self.infoboxValuesArray {
                for (index, item) in infoboxValuesArray.enumerated() {
                    if key.lowercased() == item.lowercased() {
                        var updatedValue = value.replacingOccurrences(of: "[[", with: "")
                        updatedValue = updatedValue.replacingOccurrences(of: "]]", with: "")
                        updatedValue = updatedValue.replacingOccurrences(of: "of ", with: "")
                        self.updatedInfoboxValuesArray![index] = self.updatedInfoboxValuesArray![index].replacingOccurrences(of: "pop", with: "population")
                        self.updatedInfoboxValuesArray![index] = self.updatedInfoboxValuesArray![index].capitalized
                        if checkIfClickable(string: updatedValue) {
                            self.newDictionary.updateValue([updatedValue:true], forKey: self.updatedInfoboxValuesArray![index])
                        } else {
                            self.newDictionary.updateValue([updatedValue:false], forKey: self.updatedInfoboxValuesArray![index])
                        }
                    }
                }
            }
        }
    }
    
    private func checkIfClickable(string: String) -> Bool{
        var clickable = false
        self.pages?.forEach({ page in
            if page.title.lowercased().contains(string.lowercased()) {
                clickable = true
            }
        })
        return clickable
    }
    
    private func cleanDescription(description: String, page: Page) {
        guard let startingIndex = description.firstIndex(of: "{"), let indexToSetEnding = description.firstIndex(of: "}")  else {
            return
        }
        
        let endingIndex = description.index(after: indexToSetEnding)
        var editedDescription = description
        
        // Remove the infobox string if exist
        editedDescription.replaceSubrange(startingIndex...endingIndex, with: "")
        editedDescription = editedDescription.replacingOccurrences(of: "__TOC__", with: "")
        editedDescription = editedDescription.replacingOccurrences(of: "__NOTOC__", with: "")
        editedDescription = editedDescription.replacingOccurrences(of: "|", with: "]][[")
        
        // Clean data from [[File]] and [[User]]
        var updated = editedDescription.replacingOccurrences(of: "\\[\\[File:[^\\]]+\\]\\]", with: "", options: .regularExpression)
        updated = updated.replacingOccurrences(of: "\\[\\[Category[^\\]]+\\]\\]", with: "", options: .regularExpression)
        updated = updated.replacingOccurrences(of: "\\[\\[User[^\\]]+\\]\\]", with: "", options: .regularExpression)
        
        self.descriptionClickableValuesArray = matchesForRegexInText(regex: regexSquareBrackets, text: updated)
        
        // Make the title in text bold and remove the triple quotation on it
        self.pageDescriptionAttributedString = editedDescription.withBoldText(text: "'''\(page.title)'''")
        self.pageDescriptionAttributedString = self.pageDescriptionAttributedString?.stringWithString(stringToReplace: "'''\(page.title)'''", replacedWithString: "\(page.title)")
    }
    
    private func setUpDataForClickableLabel(string: String, label: UILabel) {
        self.stringToBeCalled = string
        self.labelToBeCalled = label
        self.pages?.forEach({ page in
            if page.title == self.stringToBeCalled {
                self.pageToBeCalled = page
            }
        })
    }
    
    @objc func tappedOnLabel(_ gesture: UITapGestureRecognizer) {
        guard let label = self.labelToBeCalled,
              let stringToBeCalled = self.stringToBeCalled,
              let page = self.pageToBeCalled,
              let allPages = self.pages else {
            return
        }
        
        if gesture.didTapAttributedString(stringToBeCalled, in: label) {
            ActionManager().pushViewController(page: page, allPages: allPages)
        }
    }
    
    private func matchesForRegexInText(regex: String, text: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: regex, options: [])
            let nsString = text as NSString
            let results = regex.matches(in: text, options: [], range: NSMakeRange(0, nsString.length))
            return results.map { nsString.substring(with: $0.range)}
        } catch let error as NSError {
            print("invalid regex: \(error.localizedDescription)")
            return []
        }}
    
    private func removeBracketsFromHyperlinks(pageNameDecoded: String) -> String {
        var editedPageName = pageNameDecoded.replacingOccurrences(of: "[[", with: "")
        editedPageName = editedPageName.replacingOccurrences(of: "]]", with: "")
        return editedPageName
    }
}


