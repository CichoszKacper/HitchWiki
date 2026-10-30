//
//  MainMenuViewModel.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/10/2021.
//

import UIKit

class MainMenuViewModel: ViewModel, ViewModelProtocol {
    
    var pages = [PageSummary]()
    var filteredPages = [PageSummary]()
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
        do {
            // The database only holds articles, so User:, Template: etc. are already gone.
            let pagesToDisplay = self.excludingUnwantedTitles(try HitchwikiDatabase.shared?.allPages() ?? [])
            self.pages = pagesToDisplay
            self.filteredPages = pagesToDisplay
        } catch {
            // TODO: Alert once the Alert Manager is set up
            print("\(error)")
        }
    }

    /// Pages whose title starts with `searchText`; all pages for an empty search.
    public func search(_ searchText: String) {
        guard !searchText.isEmpty else {
            self.filteredPages = self.pages
            return
        }
        do {
            self.filteredPages = self.excludingUnwantedTitles(try HitchwikiDatabase.shared?.pages(titleStartingWith: searchText) ?? [])
        } catch {
            print("\(error)")
        }
    }

    private func excludingUnwantedTitles(_ pages: [PageSummary]) -> [PageSummary] {
        pages.filter { page in
            !self.stringsToExclude.contains { page.title.lowercased().contains($0.lowercased()) }
        }
    }
    
    func moveToPageScreen(indexRow: Int) {
        let page = self.filteredPages[indexRow]
        let pageDetailViewController = PageDetailViewController(viewModel: PageDetailViewModel())
        pageDetailViewController.populatePage(title: page.title)
        pageDetailViewController.modalPresentationStyle = .fullScreen
        UIApplication.topViewController()?.navigationController?.pushViewController(pageDetailViewController, animated: true)
    }
}
