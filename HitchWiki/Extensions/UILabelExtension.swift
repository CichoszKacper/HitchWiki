//
//  UILabelExtension.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 14/10/2021.
//

import UIKit

extension UILabel {
    func addBorder(height: Int, colour: UIColor) {
        let lineView = UIView(frame: CGRect(x: 0, y: self.frame.height - 3, width: frame.width, height: CGFloat(height)))
        lineView.backgroundColor = colour
        self.addSubview(lineView)
    }
    
    func set(color: UIColor, on substrings: [String]) {
        
        guard let text = self.text else {
            return
        }
        
        // Calculates the ranges of the substrings that needs the color change
        let ranges = substrings.map { substring -> NSRange in
            return (text as NSString).range(of: substring)
        }
        
        // Creates an attributed string and adds the color atrribute for each range
        let styledText = NSMutableAttributedString(string: text)
        
        for range in ranges {
            styledText.addAttribute(.foregroundColor, value: color, range: range)
        }
        
        // Sets the attributed text to the label
        attributedText = styledText
    }
}
