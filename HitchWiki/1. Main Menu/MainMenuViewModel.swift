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
    
    func moveToPageScreen(indexRow: Int) {
        let page = self.filteredPages[indexRow]
        let pageDetailViewController = PageDetailViewController(viewModel: PageDetailViewModel())
        pageDetailViewController.populatePage(page: page, allPages: self.pages)
        pageDetailViewController.modalPresentationStyle = .fullScreen
        UIApplication.topViewController()?.navigationController?.pushViewController(pageDetailViewController, animated: true)
    }
}
