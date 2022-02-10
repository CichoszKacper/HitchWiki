//
//  MainMenuViewModel.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/10/2021.
//

import UIKit

class MainMenuViewModel: ViewModel, ViewModelProtocol {
    
    var pages = [Page]()
    var filteredPages = [Page]()
    let stringsToExclude = ["Main Page", "MediaWiki","User","Template","Hitch","Category","Top","Help","phrasebook","Talk","What to","How to","File:","Encyclopedia","Academy","Sign Up","Portal:","Resources"]
    
    
    // MARK: - Updates
    var update: ((MainMenuViewModel.UpdateType) -> Void)?
    enum UpdateType {
        case search
        case mainMenu
    }
    
    var error: ((MainMenuViewModel.ErrorType) -> Void)?
    enum ErrorType {
        
    }
    
    // MARK: - Public Methods
    public func searchBarClicked() {
        self.update?(.search)
    }
    
    public func loadData() {
        NetworkManager().readLocalData(forName: "hitchwiki") { [weak self] result in
            switch result {
            case .success(var pagesToDisplay):
                self?.stringsToExclude.forEach({ (item) in
                    pagesToDisplay = pagesToDisplay.filter({ (page) -> Bool in
                        return !page.title.lowercased().contains(item.lowercased())
                    })
                })
                self?.pages = pagesToDisplay
                self?.filteredPages = pagesToDisplay
            case .failure(let error):
                // TODO: Alert once the Alert Manager is set up
                print("\(error)")
            }
        }
    }
    
    public func moveToPageScreen(indexRow: Int) {
        var shouldRedirect = false
        var clickedPage = self.filteredPages[indexRow].title
        self.pages.forEach({ page in
            if page.title.lowercased() == clickedPage.lowercased() {
                shouldRedirect = ((page.redirect?.title.isEmpty) == nil)
                if shouldRedirect {
                    ActionManager().pushViewController(page: page, allPages: self.pages)
                } else {
                    clickedPage = page.redirect!.title
                }
            }
        })
        if !shouldRedirect {
            self.pages.forEach({ page in
                if page.title.lowercased() == clickedPage.lowercased() {
                    ActionManager().pushViewController(page: page, allPages: self.pages)
                }
            })
        }
    }
}
