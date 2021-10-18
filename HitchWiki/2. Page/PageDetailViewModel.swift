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
    var infoboxValuesArray: [String]?
    var updatedInfoboxValuesArray: [String]?
    var newDictionary: [String:[String:Bool]] = [:]
    var pageDescriptionText: String?
    var pageDescriptionAttributedString: NSAttributedString?
    
    var stringToBeCalled: String?
    var labelToBeCalled: UILabel?
    var pageToBeCalled: Page?
    
    // MARK: - Updates
    var update: ((PageDetailViewModel.UpdateType) -> Void)?
    enum UpdateType {
        case page
    }
    
    var error: ((PageDetailViewModel.ErrorType) -> Void)?
    enum ErrorType {
        
    }

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
    
    private func cleanInfobox(description: String) {
        guard let startingIndex = description.firstIndex(of: "{"), let endingIndex = description.firstIndex(of: "}") else {
            return
        }
        
        let infoboxDescription = description[startingIndex...endingIndex]
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
            for (index, item) in self.infoboxValuesArray!.enumerated() {
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
        for (k,v) in self.newDictionary {
            print("\(k): \(v)")
        }
    }
    
    private func checkIfClickable(string: String) -> Bool{
        guard let currentPageTitle = self.page?.title else {
            return false
        }
        
        var clickable = false
        self.pages?.forEach({ page in
            if page.title.lowercased().contains(string.lowercased()) {
                clickable = true
            }
        })
        if currentPageTitle.lowercased().contains(string.lowercased()) {
            clickable = false
        }
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
        
        // Clean data from [[File]] and [[User]]
//        var updated = editedDescription.replacingOccurrences(of: "\\[\\[File:[^\\]]+\\]\\]", with: "", options: .regularExpression)
//        updated = updated.replacingOccurrences(of: "\\[\\[User[^\\]]+\\]\\]", with: "", options: .regularExpression)
        
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
              let page = self.pageToBeCalled,
              let allPages = self.pages else {
            return
        }
        
        if gesture.didTapAttributedString(stringToBeCalled, in: label) {
            let pageDetailViewController = PageDetailViewController(viewModel: PageDetailViewModel())
            pageDetailViewController.populatePage(page: page, allPages: allPages)
            pageDetailViewController.modalPresentationStyle = .fullScreen
            UIApplication.topViewController()?.navigationController?.pushViewController(pageDetailViewController, animated: true)
        }
    }
}
