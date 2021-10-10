//
//  MainMenuViewController.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 03/10/2021.
//

import UIKit

class MainMenuViewController: UIViewController {
    
    var viewModel = MainMenuViewModel()
    @IBOutlet weak var pagesTableView: UITableView!
    
    var pages = [Page](){
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
        self.loadData()
    }
    
    
    // MARK: - Private Functions
    private func loadData() {
        NetworkManager().readLocalData(forName: "hitchwiki") { [weak self] result in
            switch result {
            case .success(let pagesToDisplay):
                self?.pages = pagesToDisplay
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
        self.pages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PageTableViewCell", for: indexPath) as! PageTableViewCell
        cell.populateCell(page: self.pages[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate
extension MainMenuViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

    }
}
