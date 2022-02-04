//
//  MainMenuViewController.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/10/2021.
//

import UIKit

class MainMenuViewController: ModelledViewController<MainMenuViewModel> {
    
    @IBOutlet weak var pagesTableView: UITableView!
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var menuView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.pagesTableView.register(UINib(nibName: "PageTableViewCell", bundle: nil), forCellReuseIdentifier: "PageTableViewCell")
        self.title = "Home"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
        self.viewModel.loadData()
    }
    
    
    override func updateView(_ type: MainMenuViewModel.UpdateType) {
        switch type {
        case .search:
            self.pagesTableView.isHidden = false
            self.menuView.isHidden = true
            self.pagesTableView.reloadOnMainThread()
        case .mainMenu:
            self.menuView.isHidden = false
            self.pagesTableView.isHidden = true
        }
    }
    
    // MARK: - Private Functions
}

// MARK: - UITableViewDataSource
extension MainMenuViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.viewModel.filteredPages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PageTableViewCell", for: indexPath) as! PageTableViewCell
        cell.populateCell(page: self.viewModel.filteredPages[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate
extension MainMenuViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.viewModel.moveToPageScreen(indexRow: indexPath.row)
    }
}

// MARK: - UISearchBarDelegate
extension MainMenuViewController: UISearchBarDelegate {
    
    // Extension to SearchBar to search through the list of pages
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard !searchText.isEmpty else {
            self.viewModel.filteredPages = self.viewModel.pages
            searchBar.resignFirstResponder()
            return
        }
        
        self.viewModel.filteredPages = self.viewModel.pages.filter { ($0.title.lowercased().starts(with: searchText.lowercased()))}
        self.pagesTableView.reloadOnMainThread()
        // TODO: Allow user to search when page contains searched text, not only starts with
//        self.filteredPages = self.pages.filter { ($0.title.lowercased().contains(searchText.lowercased()))}
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        self.viewModel.searchBarClicked()
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        self.viewModel.update?(.mainMenu)
    }
}
