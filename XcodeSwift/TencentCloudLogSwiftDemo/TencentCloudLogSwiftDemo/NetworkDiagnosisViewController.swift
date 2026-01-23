//
//  NetworkDiagnosisViewController.swift
//  TencentCloudLogSwiftDemo
//
//  网络探测功能 Swift Demo - 简化版
//  展示如何使用 CLS SDK 的网络探测功能（Ping、TCPing、HTTPing、TraceRoute）
//

import UIKit

class NetworkDiagnosisViewController: UIViewController {
    
    // MARK: - UI 组件
    
    private let hostTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "请输入域名或IP，如：cloud.tencent.com"
        textField.borderStyle = .roundedRect
        textField.clearButtonMode = .whileEditing
        textField.autocapitalizationType = .none
        textField.text = "cloud.tencent.com"
        return textField
    }()
    
    private let resultTextView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.font = UIFont.systemFont(ofSize: 12)
        textView.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.borderWidth = 1.0
        textView.layer.cornerRadius = 8.0
        return textView
    }()
    
    // MARK: - 网络探测相关
    
    private var contentString = NSMutableString()
    
    // MARK: - 生命周期
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        startNetWork()
    }
    
    // MARK: - UI 设置
    
    private func setupUI() {
        view.backgroundColor = .white
        title = "网络探测 Swift Demo"

        // 添加输入框
        view.addSubview(hostTextField)
        hostTextField.translatesAutoresizingMaskIntoConstraints = false
        
        let topAnchor: NSLayoutYAxisAnchor
        let bottomAnchor: NSLayoutYAxisAnchor
        if #available(iOS 11.0, *) {
            topAnchor = view.safeAreaLayoutGuide.topAnchor
            bottomAnchor = view.safeAreaLayoutGuide.bottomAnchor
        } else {
            topAnchor = topLayoutGuide.bottomAnchor
            bottomAnchor = bottomLayoutGuide.topAnchor
        }
        
        NSLayoutConstraint.activate([
            hostTextField.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            hostTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hostTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            hostTextField.heightAnchor.constraint(equalToConstant: 44)
        ])

        // 添加按钮组
        let buttonStackView = createButtonStackView()
        view.addSubview(buttonStackView)
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttonStackView.topAnchor.constraint(equalTo: hostTextField.bottomAnchor, constant: 16),
            buttonStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            buttonStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttonStackView.heightAnchor.constraint(equalToConstant: 120)
        ])

        // 添加结果显示区域
        view.addSubview(resultTextView)
        resultTextView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            resultTextView.topAnchor.constraint(equalTo: buttonStackView.bottomAnchor, constant: 16),
            resultTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            resultTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            resultTextView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
    
    private func createButtonStackView() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.distribution = .fillEqually
        
        let pingButton = createButton(title: "Ping 探测", action: #selector(performPing))
        let tcpButton = createButton(title: "TCPing 探测", action: #selector(performTCPing))
        let httpButton = createButton(title: "HTTPing 探测", action: #selector(performHTTPing))
        let traceButton = createButton(title: "TraceRoute 追踪", action: #selector(performTraceRoute))
        
        stackView.addArrangedSubview(pingButton)
        stackView.addArrangedSubview(tcpButton)
        stackView.addArrangedSubview(httpButton)
        stackView.addArrangedSubview(traceButton)
        
        return stackView
    }
    
    private func createButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.backgroundColor = UIColor.systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    
    // MARK: - 网络探测初始化（参照 OC 版本的 startNetWork）
    
    private func startNetWork() {
        // 创建配置
        let config = ClsConfig()
        config.debuggable = true
        config.endpoint = "ap-guangzhou.cls.tencentcs.com"
        config.accessKeyId = ""  // 请替换为你的 AccessKeyId
        config.accessKeySecret = ""  // 请替换为你的 AccessKeySecret
        config.topicId = ""  // 请替换为你的 TopicId
        config.pluginAppId = "your pluginid"

        // 自定义参数
        config.userId = "user1"
        config.channel = "channel1"
        config.addCustom(withKey: "customKey1", andValue: "testValue")
        config.addCustom(withKey: "customKey2", andValue: "testValue")
        config.addCustom(withKey: "customKey3", andValue: "testValue")

        // 初始化插件
        let clsAdapter = ClsAdapter.sharedInstance()
        let plugin = CLSNetworkDiagnosisPlugin()
        _ = clsAdapter.add(unsafeBitCast(plugin, to: baseClsPlugin.self))
        _ = clsAdapter.initWith(config)

        appendLog("✅ 网络探测插件初始化成功\n请在上方输入框输入要探测的域名或IP")
    }
    
    // MARK: - 网络探测方法（参照 OC 版本的实现）
    
    @objc private func performPing() {
        guard let host = getHost() else { return }
        
        contentString.setString("")
        appendLog("\n🔄 开始 Ping 探测: \(host)")
        
        let dictionary = NSMutableDictionary()
        dictionary.setObject("newvalue", forKey: "newcustomkey" as NSCopying)
        
        ClsNetworkDiagnosis.sharedInstance().ping(
            host,
            size: 0,
            output: CLSWriter(),
            complete: { [weak self] result in
                guard let self = self else { return }
                self.contentString.append("pingResult:\(result.description)\n")
                self.appendLog(self.contentString as String)
            },
            customFiled: dictionary
        )
    }
    
    @objc private func performTCPing() {
        guard let host = getHost() else { return }
        
        contentString.setString("")
        appendLog("\n🔄 开始 TCPing 探测: \(host):80")
        
        ClsNetworkDiagnosis.sharedInstance().tcpPing(
            host,
            port: 80,
            task_timeout: 5000,
            count: 10,
            output: CLSWriter(),
            complete: { [weak self] result in
                guard let self = self else { return }
                self.contentString.append("tcpPingResult:\(result.description)\n")
                self.appendLog(self.contentString as String)
            }
        )
    }
    
    @objc private func performHTTPing() {
        guard let host = getHost() else { return }
        
        // HTTP 探测需要完整的 URL
        let url = host.hasPrefix("http") ? host : "https://\(host)"
        contentString.setString("")
        appendLog("\n🔄 开始 HTTPing 探测: \(url)")
        
        ClsNetworkDiagnosis.sharedInstance().httping(
            url,
            output: CLSWriter(),
            complate: { [weak self] result in
                guard let self = self else { return }
                if let result = result {
                    self.contentString.append("httpResult:\(result.description)\n")
                } else {
                    self.contentString.append("httpResult: 无结果\n")
                }
                self.appendLog(self.contentString as String)
            }
        )
    }
    
    @objc private func performTraceRoute() {
        guard let host = getHost() else { return }
        
        contentString.setString("")
        appendLog("\n🔄 开始 TraceRoute 追踪: \(host)")
        appendLog("⏳ 路由追踪需要一定时间，请耐心等待...")
        
        ClsNetworkDiagnosis.sharedInstance().traceRoute(
            host,
            output: CLSWriter(),
            complete: { [weak self] result in
                guard let self = self else { return }
                self.contentString.append("traceResult:\(result.content ?? "无结果")\n")
                self.appendLog(self.contentString as String)
            }
        )
    }
    
    // MARK: - 辅助方法
    
    private func getHost() -> String? {
        let host = hostTextField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        if host.isEmpty {
            appendLog("⚠️ 请输入要探测的域名或IP地址")
            return nil
        }
        return host
    }
    
    private func appendLog(_ message: String) {
        DispatchQueue.main.async {
            let status = "\(self.resultTextView.text ?? "")\n> \(message)"
            self.resultTextView.text = status
            self.resultTextView.scrollRangeToVisible(NSRange(location: self.resultTextView.text.count, length: 1))
        }
    }
}

// MARK: - CLSOutputDelegate 实现（参照 OC 版本的 CLSWriter）

class CLSWriter: NSObject, CLSOutputDelegate {
    func write(_ line: String!) {
        NSLog("CLSWriter output: \(line ?? "")")
    }
}
