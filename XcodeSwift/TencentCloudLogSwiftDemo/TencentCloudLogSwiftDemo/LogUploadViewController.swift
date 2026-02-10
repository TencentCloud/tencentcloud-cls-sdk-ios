//
//  LogUploadViewController.swift
//  TencentCloudLogSwiftDemo
//
//  Created by CLS Team on 2025/02/09.
//

import UIKit
import TencentCloudLogProducer
import TencentCloudLogProducer

class LogUploadViewController: UIViewController {
    
    private var sender: LogSender!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        title = "日志上传"
        
        setupLogSender()
        setupUI()
    }
    
    private func setupLogSender() {
        // 初始化 LogSender
        let config = ClsLogSenderConfig(
            endpoint: "ap-guangzhou.cls.tencentcs.com",
            accessKeyId: "",
            accessKey: ""
        )
        sender = LogSender.shared()
        sender.setConfig(config)
        sender.start()
    }
    
    private func setupUI() {
        // 发送日志按钮
        let sendLogBtn = UIButton(type: .system)
        sendLogBtn.frame = CGRect(x: 50, y: 150, width: view.bounds.width - 100, height: 50)
        sendLogBtn.setTitle("发送日志", for: .normal)
        sendLogBtn.setTitleColor(.black, for: .normal)
        sendLogBtn.addTarget(self, action: #selector(sendLogBtnClick), for: .touchUpInside)
        view.addSubview(sendLogBtn)
    }
    
    @objc private func sendLogBtnClick() {
        uploadLogToServer()
    }
    
    private func uploadLogToServer() {
        // 循环写入 1000 条日志
        for i in 0..<1000 {
            let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
            let jsonString = """
            {"log_index":"\(i)","write_timestamp":"\(timestamp)"}
            """
            
            // 创建日志内容
            let content = Log_Content()
            content.key = "message"
            content.value = jsonString
            
            let logItem = Log()
            logItem.contentsArray.add(content)
            logItem.time = Int64(timestamp)!
            
            // 写入日志
            ClsLogStorage.sharedInstance().write(logItem, topicId: "topicid") { success, error in
                if success {
                    print("✅ 日志写入成功（第 \(i + 1) 条），等待发送")
                } else {
                    print("❌ 日志写入失败（第 \(i + 1) 条），error: \(String(describing: error))")
                }
            }
        }
        
        // 提示用户
        showAlert(title: "日志写入", message: "已开始写入 1000 条日志，请查看控制台输出")
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
