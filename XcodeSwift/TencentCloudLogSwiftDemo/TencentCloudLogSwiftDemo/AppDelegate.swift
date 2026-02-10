//
//  AppDelegate.swift
//  TencentCloudLogSwiftDemo
//
//  Created by CLS Team on 2025/02/09.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // 创建主窗口
        window = UIWindow(frame: UIScreen.main.bounds)
        
        // 创建导航控制器
        let mainVC = MainViewController()
        let navigationController = UINavigationController(rootViewController: mainVC)
        
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
        
        return true
    }
}

