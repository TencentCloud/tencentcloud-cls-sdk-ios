//
//  SceneDelegate.swift
//  TencentCloudLogSwiftDemo
//
//  Created by CLS Team on 2025/02/09.
//

import UIKit

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // 创建主窗口
        window = UIWindow(windowScene: windowScene)
        
        // 创建导航控制器
        let mainVC = MainViewController()
        let navigationController = UINavigationController(rootViewController: mainVC)
        
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
    }
}

