//
//  MainMenuViewController.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/10/2021.
//

import UIKit

class MainMenuViewController: UIViewController {
    
    var viewModel = MainMenuViewModel()
    let stringsToExclude = ["Main Page", "MediaWiki","User","Template","Hitch","Category","Top","Help","phrasebook","Talk","What to","How to","File:","Encyclopedia","Academy","Sign Up","Portal:","Resources"]
    @IBOutlet weak var pagesTableView: UITableView!
    @IBOutlet weak var searchBar: UISearchBar!
    
    var pages = [Page](){
        didSet{
            self.pagesTableView.reloadData()
        }
    }
    
    var filteredPages = [Page](){
        didSet{
            self.pagesTableView.reloadData()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.pagesTableView.register(UINib(nibName: "PageTableViewCell", bundle: nil), forCellReuseIdentifier: "PageTableViewCell")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
        self.loadData()
    }
    
    // MARK: - Private Functions
    private func loadData() {
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
}

// MARK: - UITableViewDataSource
extension MainMenuViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.filteredPages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PageTableViewCell", for: indexPath) as! PageTableViewCell
        cell.populateCell(page: self.filteredPages[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate
extension MainMenuViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let page = self.filteredPages[indexPath.row]
        let pageDetailViewController = PageDetailViewController()
        pageDetailViewController.populatePage(page: page)
        pageDetailViewController.modalPresentationStyle = .fullScreen
        UIApplication.topViewController()?.navigationController?.pushViewController(pageDetailViewController, animated: true)
    }
}

// MARK: - UISearchBarDelegate
extension MainMenuViewController: UISearchBarDelegate {
    
    // Extension to SearchBar to search through the list of pages
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard !searchText.isEmpty else {
            self.filteredPages = self.pages
            return
        }
        
        self.filteredPages = self.pages.filter { ($0.title.lowercased().starts(with: searchText.lowercased()))}
        
        // TODO: Allow user to search when page contains searched text, not only starts with
//        self.filteredPages = self.pages.filter { ($0.title.lowercased().contains(searchText.lowercased()))}
    }
}
