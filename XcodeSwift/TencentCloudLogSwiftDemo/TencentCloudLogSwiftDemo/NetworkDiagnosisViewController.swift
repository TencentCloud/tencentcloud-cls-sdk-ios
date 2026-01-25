//
//  NetworkDiagnosisViewController.swift
//  TencentCloudLogSwiftDemo
//
//  Created by herrylv on 2026/1/23.
//  参照OC版本 ProducerExampleNetDiaController 实现
//  完整的网络探测功能示例，包括 Ping、TCPPing、TraceRoute、HttpPing

import UIKit
import TencentCloudLogProducer

/// 实现CLSOutputDelegate协议的Swift类
/// 用于接收网络探测过程中的实时输出日志
class CLSWriter: NSObject, CLSOutputDelegate {
    func write(_ line: String!) {
        print("CLSWriter output: \(line ?? "")")
    }
}

class NetworkDiagnosisViewController: UIViewController {
    
    // MARK: - UI Components
    
    private var statusLabel: UILabel!
    private var statusTextView: UITextView!
    
    // MARK: - Data
    
    private var contentString = NSMutableString()
    
    // MARK: - Constants
    
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
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "网络探测"
        contentString = NSMutableString()
        setupUI()
        initializeNetworkDiagnosis()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.backgroundColor = .white
        
        let screenWidth = UIScreen.main.bounds.width
        
        // 状态标签
        statusLabel = UILabel(frame: CGRect(
            x: padding,
            y: navBarHeight + padding * 2,
            width: screenWidth - padding * 2,
            height: cellHeight
        ))
        statusLabel.backgroundColor = .white
        statusLabel.textColor = UIColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0)
        statusLabel.font = UIFont.boldSystemFont(ofSize: 16)
        statusLabel.text = "🔍 探测中..."
        view.addSubview(statusLabel)
        
        // 结果显示TextView
        statusTextView = UITextView(frame: CGRect(
            x: padding,
            y: navBarHeight + padding * 2 + cellHeight + 10,
            width: screenWidth - padding * 2,
            height: cellHeight * 12
        ))
        statusTextView.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        statusTextView.textColor = .black
        statusTextView.font = UIFont.systemFont(ofSize: 12)
        statusTextView.text = ""
        statusTextView.textAlignment = .left
        statusTextView.layoutManager.allowsNonContiguousLayout = false
        statusTextView.isEditable = false
        statusTextView.contentOffset = CGPoint(x: 0, y: 0)
        statusTextView.layer.cornerRadius = 8
        statusTextView.layer.borderWidth = 1
        statusTextView.layer.borderColor = UIColor.lightGray.cgColor
        view.addSubview(statusTextView)
    }
    
    // MARK: - Network Diagnosis Initialization
    
    /// 初始化网络探测SDK配置
    private func initializeNetworkDiagnosis() {
        updateResult("📱 初始化网络探测SDK...")
        
        let config = ClsConfig()
        config.endpoint = "ap-guangzhou.cls.tencentcs.com"
        config.accessKeyId = ""  // 填入你的 AccessKey ID
        config.accessKeySecret = ""  // 填入你的 AccessKey Secret
        config.topicId = ""  // 填入你的 Topic ID
        config.pluginAppId = "your_plugin_id"
        
        // 自定义参数
        config.userId = "user1"
        config.channel = "ios_swift_demo"
        config.addCustom(withKey: "app_version", andValue: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
        config.addCustom(withKey: "device_model", andValue: UIDevice.current.model)
        config.addCustom(withKey: "system_version", andValue: UIDevice.current.systemVersion)
        
        let clsAdapter = ClsAdapter.sharedInstance()
        let plugin = CLSNetworkDiagnosisPlugin()
        _ = clsAdapter.add(unsafeBitCast(plugin, to: baseClsPlugin.self))
        _ = clsAdapter.initWith(config)
        
        updateResult("✅ SDK初始化完成\n")
        
        // 延迟执行网络探测，避免UI卡顿
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.performNetworkTests()
        }
    }
    
    // MARK: - Network Tests
    
    /// 执行完整的网络探测测试流程
    private func performNetworkTests() {
        updateStatusLabel("🔍 正在执行网络探测...")
        
        // 准备自定义字段
        let customFields = NSMutableDictionary()
        customFields["detect_scene"] = "network_diagnosis_demo"
        customFields["test_timestamp"] = "\(Date().timeIntervalSince1970)"
        
        updateResult("━━━━━━━━━━━━━━━━━━━━━━")
        updateResult("开始网络探测测试")
        updateResult("━━━━━━━━━━━━━━━━━━━━━━\n")
        
        // 1. Ping 探测
        performPing(customFields: customFields)
    }
    
    /// 执行 Ping 探测
    private func performPing(customFields: NSMutableDictionary) {
        updateResult("1️⃣ Ping 探测")
        updateResult("   目标：cloud.tencent.com")
        updateResult("   包大小：64 字节")
        
        ClsNetworkDiagnosis.sharedInstance().ping(
            "cloud.tencent.com",
            size: 64,
            output: CLSWriter(),
            complete: { [weak self] result in
                guard let self = self else { return }
                
                if result != nil {
                    self.updateResult("   ✅ Ping 完成")
                    self.updateResult("   结果：\(result.description)")
                } else {
                    self.updateResult("   ❌ Ping 失败")
                }
                self.updateResult("")
                
                // 继续下一个测试
                self.performTCPPing(customFields: customFields)
            },
            customFiled: customFields
        )
    }
    
    /// 执行 TCPPing 探测
    private func performTCPPing(customFields: NSMutableDictionary) {
        updateResult("2️⃣ TCPPing 探测")
        updateResult("   目标：cloud.tencent.com:443")
        updateResult("   次数：10 次")
        updateResult("   超时：5000 ms")
        
        ClsNetworkDiagnosis.sharedInstance().tcpPing(
            "cloud.tencent.com",
            port: 443,
            task_timeout: 5000,
            count: 10,
            output: CLSWriter(),
            complete: { [weak self] result in
                guard let self = self else { return }
                
                if result != nil {
                    self.updateResult("   ✅ TCPPing 完成")
                    self.updateResult("   结果：\(result.description)")
                } else {
                    self.updateResult("   ❌ TCPPing 失败")
                }
                self.updateResult("")
                
                // 继续下一个测试
                self.performTraceRoute(customFields: customFields)
            },
            customFiled: customFields
        )
    }
    
    /// 执行 TraceRoute 探测
    private func performTraceRoute(customFields: NSMutableDictionary) {
        updateResult("3️⃣ TraceRoute 探测")
        updateResult("   目标：cloud.tencent.com")
        updateResult("   最大跳数：30")
        
        ClsNetworkDiagnosis.sharedInstance().traceRoute(
            "cloud.tencent.com",
            output: CLSWriter(),
            complete: { [weak self] result in
                guard let self = self else { return }
                
                if result != nil {
                    self.updateResult("   ✅ TraceRoute 完成")
                    let content = result.content
                    // TraceRoute 结果可能很长，只显示摘要
                    let lines = content.components(separatedBy: "\n")
                    self.updateResult("   共 \(lines.count) 跳")
                    if lines.count > 0 {
                        self.updateResult("   首跳：\(lines[0])")
                    }
                    if lines.count > 1 {
                        self.updateResult("   末跳：\(lines[lines.count - 1])")
                    }
                } else {
                    self.updateResult("   ❌ TraceRoute 失败")
                }
                self.updateResult("")
                
                // 继续下一个测试
                self.performHttpPing(customFields: customFields)
            },
            maxTtl: 30,
            customFiled: customFields
        )
    }
    
    /// 执行 HttpPing 探测
    private func performHttpPing(customFields: NSMutableDictionary) {
        updateResult("4️⃣ HttpPing 探测")
        updateResult("   URL：https://ap-guangzhou.cls.tencentcs.com/ping")
        
        ClsNetworkDiagnosis.sharedInstance().httping(
            "https://ap-guangzhou.cls.tencentcs.com/ping",
            output: CLSWriter(),
            complate: { [weak self] result in
                guard let self = self else { return }
                
                if let result = result {
                    self.updateResult("   ✅ HttpPing 完成")
                    self.updateResult("   结果：\(result.description)")
                } else {
                    self.updateResult("   ❌ HttpPing 失败")
                }
                self.updateResult("")
                
                // 所有测试完成
                self.allTestsCompleted()
            },
            customFiled: customFields
        )
    }
    
    /// 所有测试完成
    private func allTestsCompleted() {
        updateResult("━━━━━━━━━━━━━━━━━━━━━━")
        updateResult("✅ 所有网络探测测试完成！")
        updateResult("━━━━━━━━━━━━━━━━━━━━━━")
        updateStatusLabel("✅ 探测完成")
    }
    
    // MARK: - Helper Methods
    
    /// 更新状态标签
    private func updateStatusLabel(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = text
        }
    }
    
    /// 更新结果显示
    private func updateResult(_ append: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let currentText = self.statusTextView.text ?? ""
            let newText = currentText.isEmpty ? append : "\(currentText)\n\(append)"
            self.statusTextView.text = newText
            
            // 滚动到底部
            if newText.count > 0 {
                let range = NSRange(location: newText.count - 1, length: 1)
                self.statusTextView.scrollRangeToVisible(range)
            }
        }
    }
}
