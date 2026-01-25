//
//  AppDelegate.swift
//  TencentCloundLogSwiftDemo
//
//  Created by herrylv on 2022/5/26.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let utils = DemoUtils.shared
        utils.endpoint = "ap-guangzhou.cls.tencentcs.com"
        utils.accessKeyId = "";
        utils.accessKeySecret = "";
        utils.topic = "";
        
        print("endpoint:",utils.endpoint)
        print("accessKeyId:",utils.accessKeyId)
        print("accessKeySecret:",utils.accessKeySecret)
        print("topic:",utils.topic)
        
        // 对于iOS 12及以下，在这里创建window（iOS 13+使用SceneDelegate）
        if #available(iOS 13.0, *) {
            // iOS 13+ 使用 SceneDelegate
        } else {
            // iOS 12及以下，在AppDelegate中创建window
            self.window = UIWindow(frame: UIScreen.main.bounds)
            let mainViewController = MainViewController()
            let navigationController = UINavigationController(rootViewController: mainViewController)
            self.window?.rootViewController = navigationController
            self.window?.makeKeyAndVisible()
        }
        
        return true
    }


}

