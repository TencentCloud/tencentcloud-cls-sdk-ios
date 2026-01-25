//
//  SceneDelegate.swift
//  TencentCloudLogSwiftDemo
//
//  Created by herrylv on 2022/5/26.
//

import UIKit

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // 使用代码创建UI，不依赖Storyboard
        let window = UIWindow(windowScene: windowScene)
        
        // 创建主界面并嵌入导航控制器
        let mainViewController = MainViewController()
        let navigationController = UINavigationController(rootViewController: mainViewController)
        
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        
        self.window = window
    }
}
