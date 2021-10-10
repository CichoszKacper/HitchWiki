//
//  NetworkManager.swift
//  HitchWiki
//
//  Created by Kacper Cichosz on 10/10/2021.
//

import Foundation

enum NetworkError: Error {
    case noDataAvailable
    case canNotProcessData
}

struct NetworkManager {
    func readLocalData(forName name: String, completion: @escaping (Result<[Page], NetworkError>) -> Void) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let jsonData = try decoder.decode(DataModel.self, from: data)
            DispatchQueue.main.async {
                completion(.success(jsonData.mediawiki.page))
            }
        } catch {
            completion(.failure(.canNotProcessData))
        }
    }
}
