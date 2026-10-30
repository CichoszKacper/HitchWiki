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

extension UILabel {
    /// Index of the character under `point` (in the label's coordinates), or nil when the tap is not on any text.
    /// Lays the text out with TextKit using the attributed text as-is, so mixed fonts (headings) line up.
    func characterIndex(at point: CGPoint) -> Int? {
        guard let attributedText = self.attributedText, attributedText.length > 0 else {
            return nil
        }

        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: CGSize(width: self.bounds.width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = self.numberOfLines
        textContainer.lineBreakMode = self.numberOfLines == 0 ? .byWordWrapping : self.lineBreakMode
        layoutManager.addTextContainer(textContainer)

        // UILabel centres its text vertically when it is taller than the text.
        let textHeight = layoutManager.usedRect(for: textContainer).height
        let pointInText = CGPoint(x: point.x, y: point.y - max(0, (self.bounds.height - textHeight) / 2))

        let glyphIndex = layoutManager.glyphIndex(for: pointInText, in: textContainer)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        // glyphIndex(for:) returns the nearest glyph, so ignore taps in the empty space after a line.
        guard glyphRect.insetBy(dx: -4, dy: -4).contains(pointInText) else {
            return nil
        }
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}
