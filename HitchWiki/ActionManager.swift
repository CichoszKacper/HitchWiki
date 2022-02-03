//
//  ActionManager.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 02/02/2022.
//

import UIKit

class ActionManager {
    func pushViewController(page: Page, allPages: [Page]) {
        let pageDetailViewController = PageDetailViewController(viewModel: PageDetailViewModel())
        pageDetailViewController.populatePage(page: page, allPages: allPages)
        pageDetailViewController.modalPresentationStyle = .fullScreen
        UIApplication.topViewController()?.navigationController?.pushViewController(pageDetailViewController, animated: true)
    }
}
