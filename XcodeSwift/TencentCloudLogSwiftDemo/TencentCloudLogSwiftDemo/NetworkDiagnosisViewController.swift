//
//  NetworkDiagnosisViewController.swift
//  TencentCloudLogSwiftDemo
//
//  Created by herrylv on 2026/1/23.
//  参照OC版本 ProducerExampleNetDiaController 实现

import UIKit
import TencentCloudLogProducer

/// 实现CLSOutputDelegate协议的Swift类
class CLSWriter: NSObject, CLSOutputDelegate {
    var host: String = ""
    
    func write(_ line: String!) {
        print("CLSWriter output: \(line ?? "")")
    }
}

class NetworkDiagnosisViewController: UIViewController {
    
    // UI组件
    private var statusTextView: UITextView!
    
    // 数据
    private var contentString = NSMutableString()
    
    // 常量定义（参照OC版本的宏定义）
    private let padding: CGFloat = 20
    private let cellHeight: CGFloat = 44
    private var navBarHeight: CGFloat {
        // 导航栏+状态栏高度
        if #available(iOS 11.0, *) {
            return (navigationController?.navigationBar.frame.height ?? 44) + view.safeAreaInsets.top
        } else {
            return 88
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "网络探测"
        contentString = NSMutableString()
        initViews()
        startNetWork()
    }
    
    private func initViews() {
        view.backgroundColor = .white
        
        let screenWidth = UIScreen.main.bounds.width
        
        // 标签
        let label = UILabel(frame: CGRect(
            x: padding,
            y: navBarHeight + padding * 2,
            width: screenWidth - padding * 2,
            height: cellHeight
        ))
        label.backgroundColor = .white
        label.textColor = .black
        label.text = "探测中..."
        view.addSubview(label)
        
        // 结果显示TextView
        statusTextView = UITextView(frame: CGRect(
            x: padding,
            y: navBarHeight + padding * 2 + cellHeight,
            width: screenWidth - padding * 2,
            height: cellHeight * 12
        ))
        statusTextView.backgroundColor = .white
        statusTextView.textColor = .black
        statusTextView.text = ""
        statusTextView.textAlignment = .left
        statusTextView.layoutManager.allowsNonContiguousLayout = false
        statusTextView.isEditable = false
        statusTextView.contentOffset = CGPoint(x: 0, y: 0)
        view.addSubview(statusTextView)
    }
    
    // 更新结果（参照OC版本的UpdateReult方法）
    private func updateResult(_ append: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let status = "\(self.statusTextView.text ?? "")\n> \(append)"
            self.statusTextView.text = status
            
            // 滚动到底部
            let range = NSRange(location: self.statusTextView.text.count, length: 1)
            self.statusTextView.scrollRangeToVisible(range)
        }
    }
    
    // 初始化网络探测SDK（参照OC版本的startNetWork方法）
    private func startNetWork() {
        let config = ClsConfig()
        config.endpoint = "ap-guangzhou.cls.tencentcs.com"
        config.accessKeyId = ""
        config.accessKeySecret = ""
        config.topicId = ""
        config.pluginAppId = "your pluginid"
        
        // 自定义参数
        config.userId = "user1"
        config.channel = "channel1"
        config.addCustom(withKey: "customKey1", andValue: "testValue")
        config.addCustom(withKey: "customKey2", andValue: "testValue")
        config.addCustom(withKey: "customKey3", andValue: "testValue")
        
        let clsAdapter = ClsAdapter.sharedInstance()
        let plugin = CLSNetworkDiagnosisPlugin()
        _ = clsAdapter.add(unsafeBitCast(plugin, to: baseClsPlugin.self))
        _ = clsAdapter.initWith(config)
        
        // ping探测（参照OC版本，自动开始ping）
        let dictionary = NSMutableDictionary()
        dictionary["newcustomkey"] = "newvalue"
        
        ClsNetworkDiagnosis.sharedInstance().ping(
            "127.0.0.1",
            size: 0,
            output: CLSWriter(),
            complete: { [weak self] result in
                guard let self = self else { return }
                let resultStr = "pingResult:\(result.description ?? "无结果")\n"
                self.contentString.append(resultStr)
                self.updateResult(self.contentString as String)
            },
            customFiled: dictionary
        )
        
        // 以下是其他探测方法示例（已注释，可按需启用）
        
        // tcpPing
//        ClsNetworkDiagnosis.sharedInstance().tcpPing(
//            "127.0.0.1",
//            port: 80,
//            task_timeout: 5000,
//            count: 10,
//            output: CLSWriter()
//        ) { [weak self] result in
//            guard let self = self else { return }
//            let resultStr = "tcpPingResult:\(result?.description ?? "无结果")\n"
//            self.contentString.append(resultStr)
//            self.updateResult(self.contentString as String)
//        }
        
        // traceRoute
//        ClsNetworkDiagnosis.sharedInstance().traceRoute(
//            "127.0.0.1",
//            output: CLSWriter()
//        ) { [weak self] result in
//            guard let self = self else { return }
//            let resultStr = "traceResult:\(result?.content ?? "无结果")\n"
//            self.contentString.append(resultStr)
//            self.updateResult(self.contentString as String)
//        }
        
        // httping
//        ClsNetworkDiagnosis.sharedInstance().httping(
//            "https://ap-guangzhou.cls.tencentcs.com/ping",
//            output: CLSWriter()
//        ) { [weak self] result in
//            guard let self = self else { return }
//            let resultStr = "httpResult:\(result?.description ?? "无结果")\n"
//            self.contentString.append(resultStr)
//            self.updateResult(self.contentString as String)
//        }
    }
}
