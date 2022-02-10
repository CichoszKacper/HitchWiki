//
//  UITextViewExtension.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/02/2022.
//

import UIKit

extension UITextView {
    
    func addHyperLinksAndSectionsToText(originalText: NSAttributedString, hyperLinks: [String], urls: [String: [String:String]], sections: [String], subsections: [String], boldText: [String], italicText: [String]) {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        let attributedOriginalText = NSMutableAttributedString(attributedString: originalText)
        for hyperLink in hyperLinks {
            attributedOriginalText.setHyperlinkForAllOccurances(hyperLink)
        }
        for (url,group) in urls {
            for (link, description) in group {
                attributedOriginalText.setURLForAllOccurances(url, link: link, description: description)
            }
        }
        for section in sections {
            attributedOriginalText.setSection(section)
        }
        for subsection in subsections {
            attributedOriginalText.setSubsection(subsection)
        }
        for text in italicText {
            attributedOriginalText.setItalicText(text)
        }
        for text in boldText {
            attributedOriginalText.setBoldText(text)
        }
        attributedOriginalText.setBulletpointColor("*", color: UIColor.systemTeal)
        attributedOriginalText.setBulletpointColor("**", color: UIColor.systemRed)
        self.linkTextAttributes = [:]
        var updatedString = attributedOriginalText.stringWithString(stringToReplace: "[[", replacedWithString: "")
        for (url,group) in urls {
            for (_, description) in group {
                updatedString = updatedString.stringWithString(stringToReplace: url, replacedWithString: description)
            }
        }
        updatedString = updatedString.stringWithString(stringToReplace: "]]", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "====", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "===", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "==", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "'''", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "''", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "**", replacedWithString: "     -")
        updatedString = updatedString.stringWithString(stringToReplace: "*", replacedWithString: "•")
        self.attributedText = updatedString
    }
}
