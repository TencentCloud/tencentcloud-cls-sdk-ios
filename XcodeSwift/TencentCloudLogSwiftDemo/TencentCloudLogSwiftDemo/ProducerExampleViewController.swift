//
//  ProducerExampleViewController.swift
//  TencentCloudLogSwiftDemo
//
//  参照OC版本的 ProducerExampleController 实现
//  基本配置和日志发送页面

import UIKit
import TencentCloudLogProducer

class ProducerExampleViewController: BaseViewController {
    
    private var showParamLabel: UILabel!
    private var resTextView: UITextView!
    private var sender: LogSender!
    private var client: ClsLogProducerClient!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "基本配置"
        view.backgroundColor = .white
        
        initViews()
        initLogProducer()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(changeText),
            name: Notification.Name(rawValue: "test"),
            object: nil
        )
    }
    
    private func initViews() {
        // 参数显示标签
        let utils = DemoUtils.shared
        let info = """
        endpoint:\(utils.endpoint)
        accessKeyId:\(utils.accessKeyId)
        accessKeySecret:\(utils.accessKeySecret)
        topic:\(utils.topic)
        """
        
        showParamLabel = createLabel(
            title: info,
            x: 0,
            y: 0,
            width: BaseViewController.screenWidth - BaseViewController.padding * 2,
            height: BaseViewController.cellHeight * 3
        )
        showParamLabel.numberOfLines = 0
        showParamLabel.font = UIFont.systemFont(ofSize: 12)
        showParamLabel.sizeToFit()
        
        // 发送日志按钮
        _ = createButton(
            title: "发送日志",
            action: #selector(sendLog),
            x: 0,
            y: BaseViewController.cellHeight * 4
        )
        
        // 销毁Producer按钮
        _ = createButton(
            title: "销毁Producer",
            action: #selector(destroyProducer),
            x: BaseViewController.cellWidth + BaseViewController.padding,
            y: BaseViewController.cellHeight * 4
        )
        
        // 结果显示文本框
        resTextView = createTextView(
            text: "",
            x: 0,
            y: BaseViewController.cellHeight * 5 + BaseViewController.padding,
            width: BaseViewController.screenWidth - BaseViewController.padding * 2,
            height: BaseViewController.cellHeight * 8
        )
        resTextView.isEditable = false
        resTextView.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
    }
    
    private func initLogProducer() {
        let utils = DemoUtils.shared
        let config = ClsLogSenderConfig(
            endpoint: utils.endpoint,
            accessKeyId: utils.accessKeyId,
            accessKey: utils.accessKeySecret
        )
        sender = LogSender.shared()
        sender.setConfig(config)
        sender.start()
    }
    
    @objc private func changeText(notification: Notification) {
        DispatchQueue.main.async {
            self.resTextView.text = notification.object as? String ?? ""
        }
    }
    
    @objc private func sendLog() {
        for i in 0..<1 {
            let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
            let jsonString = """
            {"log_index":"\(i)","write_timestamp":"\(timestamp)"}
            """
            
            let content = Log_Content()
            content.key = "message"
            content.value = jsonString
            
            let logItem = Log()
            logItem.contentsArray.add(content)
            logItem.time = Int64(timestamp)!
            
            ClsLogStorage.sharedInstance().write(logItem, topicId: "topicid") { success, error in
                if success {
                    print("日志写入成功（第 \(i + 1) 条），等待发送")
                } else {
                    print("日志写入失败（第 \(i + 1) 条），error: \(error.debugDescription)")
                }
            }
        }
        
        showAlert(message: "已发送日志")
    }
    
    @objc private func destroyProducer() {
        showAlert(message: "Producer开始销毁")
        // client?.destroyClsLogProducer()
    }
    
    private func showAlert(message: String) {
        let alert = UIAlertController(title: "提示", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
