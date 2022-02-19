//
//  ViewModel.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 15/10/2021.
//

import Foundation

class ViewModel {

    enum BaseType {
        case beginLoading
        case endLoading
    }

    var base: ((BaseType) -> Void)?
    
    public func moveToPageScreen(indexRow: Int, pages: [Page], filteredPages: [Page]) {
        var shouldRedirect = false
        var clickedPage = filteredPages[indexRow].title
        pages.forEach({ page in
            if page.title.lowercased() == clickedPage.lowercased() {
                shouldRedirect = ((page.redirect?.title.isEmpty) == nil)
                if shouldRedirect {
                    ActionManager().pushViewController(page: page, allPages: pages)
                } else {
                    clickedPage = page.redirect!.title
                }
            }
        })
        if !shouldRedirect {
            pages.forEach({ page in
                if page.title.lowercased() == clickedPage.lowercased() {
                    ActionManager().pushViewController(page: page, allPages: pages)
                }
            })
        }
    }
}
