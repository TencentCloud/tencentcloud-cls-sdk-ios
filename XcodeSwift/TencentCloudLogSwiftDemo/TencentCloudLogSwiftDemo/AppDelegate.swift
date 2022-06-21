//
//  AppDelegate.swift
//  TencentCloundLogSwiftDemo
//
//  Created by herrylv on 2022/5/26.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



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
        return true
    }


}

