//
//  PageDetailViewController.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 12/10/2021.
//

import UIKit
import Algorithms

class PageDetailViewController: UIViewController {
    @IBOutlet weak var pageDescription: UILabel!
    @IBOutlet weak var infoboxStackView: UIStackView!
    @IBOutlet weak var countryTitleLabel: UILabel!
    @IBOutlet weak var countryLanguageLabel: UILabel!
//    @IBOutlet weak var capitalLabel: UILabel!
//    @IBOutlet weak var populationLabel: UILabel!
//    @IBOutlet weak var currencyLabel: UILabel!
    
    var infoboxValuesArray: [String]?
    var updatedInfoboxValuesArray: [String]?
    var pageDescriptionText: String?
    var pageDescriptionAttributedString: NSAttributedString?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.loadData()
        self.navigationController?.isNavigationBarHidden = false
    }
    
    func loadData() {
        if let uwrappedUpdatedArray = self.updatedInfoboxValuesArray {
            if (uwrappedUpdatedArray[0].contains(":")) || (uwrappedUpdatedArray[1].contains(":")) {
                self.infoboxStackView.isHidden = false
                
                // TODO: Verify if the data for each label loaded properly, otherwise hide label
                self.countryTitleLabel.text = uwrappedUpdatedArray[0]
                self.countryLanguageLabel.text = uwrappedUpdatedArray[1]
            }
        }
        self.pageDescription.attributedText = self.pageDescriptionAttributedString
    }
    
    func populatePage(page: Page) {
        guard let description = page.revision.text.text else {
            return
        }

        if description.lowercased().contains("{{infobox") {
            self.cleanInfobox(description: description)
        }

        self.cleanDescription(description: description, page: page)
    }
    
    private func cleanInfobox(description: String) {
        guard let startingIndex = description.firstIndex(of: "{"), let endingIndex = description.firstIndex(of: "}") else {
            return
        }
        
        let infoboxDescription = description[startingIndex...endingIndex]
        let rows = infoboxDescription.dropFirst().dropLast().split(separator: "|")
        let infoboxDictionary = rows.dropFirst().reduce(into: [String:String]()) {
            guard let index = $1.firstIndex(of: "=") else { return }
            let key = String($1[$1.startIndex..<index]).trimmingCharacters(in: .whitespaces)
            let value = String($1[$1.index(after: index)..<$1.endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            $0[key] = value
        }
        
        self.infoboxValuesArray = ["country","language","pop","currency","BW"]
        self.updatedInfoboxValuesArray = self.infoboxValuesArray
        for (key,value) in infoboxDictionary {
            for (index, item) in self.infoboxValuesArray!.enumerated() {
                if key.lowercased() == item.lowercased() {
                    self.updatedInfoboxValuesArray![index] = self.updatedInfoboxValuesArray![index].capitalized
                    self.updatedInfoboxValuesArray![index].append(": \(value.replacingOccurrences(of: "of ", with: ""))")
                }
            }
        }
    }
    
    private func cleanDescription(description: String, page: Page) {
        guard let startingIndex = description.firstIndex(of: "{"), let indexToSetEnding = description.firstIndex(of: "}")  else {
            return
        }
        
        let endingIndex = description.index(after: indexToSetEnding)
        self.navigationItem.title = page.title
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
}

extension String {
    func withBoldText(text: String, font: UIFont? = nil) -> NSAttributedString {
        let _font = font ?? UIFont.systemFont(ofSize: 20, weight: .regular)
        let fullString = NSMutableAttributedString(string: self, attributes: [NSAttributedString.Key.font: _font])
        let boldFontAttribute: [NSAttributedString.Key: Any] = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: _font.pointSize)]
        let range = (self as NSString).range(of: text)
        fullString.addAttributes(boldFontAttribute, range: range)
        return fullString
    }
}

extension NSAttributedString {
    func stringWithString(stringToReplace: String, replacedWithString newStringPart: String) -> NSMutableAttributedString
    {
        let mutableAttributedString = mutableCopy() as! NSMutableAttributedString
        let mutableString = mutableAttributedString.mutableString
        while mutableString.contains(stringToReplace) {
            let rangeOfStringToBeReplaced = mutableString.range(of: stringToReplace)
            mutableAttributedString.replaceCharacters(in: rangeOfStringToBeReplaced, with: newStringPart)
        }
        return mutableAttributedString
    }
}


