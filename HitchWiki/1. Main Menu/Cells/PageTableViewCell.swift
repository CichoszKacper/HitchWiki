//
//  PageTableViewCell.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 10/10/2021.
//

import UIKit

class PageTableViewCell: UITableViewCell {
    @IBOutlet weak var pageTextLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }
    
    func populateCell(page: Page) {
        self.pageTextLabel.text = page.title
    }
}
