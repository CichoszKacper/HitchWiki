//
//  NSMutableAttributedStringExtension.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/02/2022.
//

import UIKit

extension NSMutableAttributedString{
    
    func setHyperlinkForAllOccurances(_ textToFind: String) {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        let inputLength = self.string.count
        let searchLength = textToFind.count
        var range = NSRange(location: 0, length: self.length)
        guard let encodedText = textToFind.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }
        
        while (range.location != NSNotFound) {
            range = (self.string as NSString).range(of: textToFind, options: [], range: range)
            if (range.location != NSNotFound) {
                self.addAttribute(NSAttributedString.Key.link,
                                  value: encodedText,
                                  range: NSRange(location: range.location,
                                                 length: searchLength))
                self.addAttribute(NSAttributedString.Key.paragraphStyle,
                                  value: style,
                                  range: NSRange(location: range.location,
                                                 length: searchLength))
                self.addAttribute(NSAttributedString.Key.font,
                                  value: UIFont.boldSystemFont(ofSize: 20),
                                  range: NSRange(location: range.location,
                                                 length: searchLength))
                range = NSRange(location: range.location + range.length,
                                length: inputLength - (range.location + range.length))
            }
        }
        self.mutableString.replacingOccurrences(of: "[[", with: "")
        self.mutableString.replacingOccurrences(of: "]]", with: "")
    }
}