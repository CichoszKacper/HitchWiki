//
//  UITextViewExtension.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/02/2022.
//

import UIKit

extension UITextView {
    
    func addHyperLinksAndSectionsToText(originalText: NSAttributedString, hyperLinks: [String], sections: [String], subsections: [String]) {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        let attributedOriginalText = NSMutableAttributedString(attributedString: originalText)
        for hyperLink in hyperLinks {
            attributedOriginalText.setHyperlinkForAllOccurances(hyperLink)
        }
        for section in sections {
            attributedOriginalText.setSection(section)
        }
        for subsection in subsections {
            attributedOriginalText.setSubsection(subsection)
        }
        self.linkTextAttributes = [:]
        var updatedString = attributedOriginalText.stringWithString(stringToReplace: "[[", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "]]", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "====", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "===", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "==", replacedWithString: "")
        self.attributedText = updatedString
    }
}
