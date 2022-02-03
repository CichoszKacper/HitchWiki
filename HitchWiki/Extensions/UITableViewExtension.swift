//
//  UITableViewExtension.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/02/2022.
//

import UIKit

extension UITableView {
    func reloadOnMainThread() {
        Thread.runOnMain {
            self.reloadData()
        }
    }
}
