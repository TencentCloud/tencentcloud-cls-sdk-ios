//
//  NetworkDetectViewController.swift
//  TencentCloudLogSwiftDemo
//
//  Created by CLS Team on 2025/02/09.
//

import UIKit
import TencentCloudLogProducer
import TencentCloudLogProducer

class NetworkDetectViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        title = "网络探测"
        
        setupNetworkDiagnosis()
        setupUI()
    }
    
    private func setupNetworkDiagnosis() {
        // 初始化网络探测发送接口
        let config = ClsLogSenderConfig(
            endpoint: "ap-guangzhou-open.cls.tencentcs.com",
            accessKeyId: "",
            accessKey: ""
        )
        ClsNetworkDiagnosis.sharedInstance().setupLogSender(with: config, netToken: "")
        ClsNetworkDiagnosis.sharedInstance().setUserEx(["user_key1": "user_value1"])
    }
    
    private func setupUI() {
        // 按钮配置数组
        let btnTitles = ["httpping", "tcpping", "ping", "mtr", "dns"]
        let btnY: CGFloat = 100
        let btnHeight: CGFloat = 50
        let btnWidth = view.bounds.width - 100
        let marginY: CGFloat = 20
        
        // 批量创建按钮
        for (index, title) in btnTitles.enumerated() {
            let detectBtn = UIButton(type: .system)
            detectBtn.frame = CGRect(
                x: 50,
                y: btnY + CGFloat(index) * (btnHeight + marginY),
                width: btnWidth,
                height: btnHeight
            )
            detectBtn.setTitle(title, for: .normal)
            detectBtn.setTitleColor(.black, for: .normal)
            detectBtn.tag = 100 + index
            detectBtn.addTarget(self, action: #selector(networkDetectBtnClick(_:)), for: .touchUpInside)
            view.addSubview(detectBtn)
        }
    }
    
    @objc private func networkDetectBtnClick(_ sender: UIButton) {
        var detectType = ""
        
        switch sender.tag {
        case 100:
            detectType = "httpping"
            callHttppingAPI()
        case 101:
            detectType = "tcpping"
            callTcppingAPI()
        case 102:
            detectType = "ping"
            callPingAPI()
        case 103:
            detectType = "mtr"
            callMtrAPI()
        case 104:
            detectType = "dns"
            callDnsAPI()
        default:
            break
        }
        
        print("🚀 开始执行 \(detectType) 探测")
    }
    
    // MARK: - 各网络探测接口调用
    
    private func callHttppingAPI() {
        let request = CLSHttpRequest()
        request.detectEx = ["key1": "value1"]
        request.domain = "https://sa-saopaulo.cls.tencentcs.com/ping"
        
        ClsNetworkDiagnosis.sharedInstance().httpingv2(request) { result in
            print("📡 HTTPing 结果: \(String(describing: result))")
        }
    }
    
    private func callTcppingAPI() {
        let request = CLSTcpRequest()
        request.detectEx = ["key1": "value1"]
        request.domain = "www.tencentcloud.com"
        request.port = 443
        request.maxTimes = 10
        
        ClsNetworkDiagnosis.sharedInstance().tcpPingv2(request) { result in
            print("📡 TCPing 结果: \(String(describing: result))")
        }
    }
    
    private func callPingAPI() {
        let request = CLSPingRequest()
        request.detectEx = ["key1": "value1"]
        request.domain = "127.0.0.1"
        
        ClsNetworkDiagnosis.sharedInstance().pingv2(request) { result in
            print("📡 Ping 结果: \(String(describing: result))")
        }
    }
    
    private func callMtrAPI() {
        let request = CLSMtrRequest()
        request.detectEx = ["key1": "value1"]
        request.domain = "www.baidu.com"
        
        ClsNetworkDiagnosis.sharedInstance().mtr(request) { result in
            print("📡 MTR 结果: \(String(describing: result))")
        }
    }
    
    private func callDnsAPI() {
        let request = CLSDnsRequest()
        request.detectEx = ["key1": "value1"]
        request.domain = "www.baidu.com"
        
        ClsNetworkDiagnosis.sharedInstance().dns(request) { result in
            print("📡 DNS 结果: \(String(describing: result))")
        }
    }
}
