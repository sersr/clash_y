//
//  MihomoServiceProtocol.swift
//  Runner
//
//  Created by aote on 2026/9/11.
//


import Foundation

@objc
protocol MihomoServiceProtocol {

    func start(
        configPath: String,
        reply: @escaping ([String:Any]) -> Void
    )

    func stop(
        reply: @escaping ([String:Any]) -> Void
    )

    func restart(
        configPath: String,
        reply: @escaping ([String:Any]) -> Void
    )

    func status(
        reply: @escaping ([String:Any]) -> Void
    )
}
