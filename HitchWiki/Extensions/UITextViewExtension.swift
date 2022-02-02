//
//  UITextViewExtension.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/02/2022.
//

import UIKit

extension UITextView {
    
    func addHyperLinksToText(originalText: NSAttributedString, hyperLinks: [String]) {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        let attributedOriginalText = NSMutableAttributedString(attributedString: originalText)
        for hyperLink in hyperLinks {
            attributedOriginalText.setHyperlinkForAllOccurances(hyperLink)
        }
        
        self.linkTextAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.systemBlue,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        var updatedString = attributedOriginalText.stringWithString(stringToReplace: "[[", replacedWithString: "")
        updatedString = updatedString.stringWithString(stringToReplace: "]]", replacedWithString: "")
        self.attributedText = updatedString
    }
}
