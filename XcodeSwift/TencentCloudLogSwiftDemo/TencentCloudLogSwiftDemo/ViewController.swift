//
//  ViewController.swift
//  TencentCloundLogSwiftDemo
//
//  Created by herrylv on 2022/5/26.
//

import UIKit
import TencentCloudLogProducer
class ViewController: UIViewController {
    @IBOutlet weak var showparam: UILabel!
    @IBOutlet weak var resText: UITextView!
    private var sender: LogSender!
    fileprivate var client:     ClsLogProducerClient!
    override func viewDidLoad() {
        super.viewDidLoad()
        let utils = DemoUtils.shared
        let info = "endpoint:\(utils.endpoint)\n accessKeyId:\(utils.accessKeyId)\n accessKeySecret:\(utils.accessKeySecret)\ntopic:\(utils.topic)"
        self.showparam.text = info
        self.showparam.numberOfLines = 0
        self.showparam.sizeToFit()
        self.initLogProducer();
        
        NotificationCenter.default.addObserver(self , selector: #selector(changeText), name: Notification.Name(rawValue: "test"), object: nil);
    }
    
    @objc func changeText(noti:Notification){
        
        DispatchQueue.main.async {
            self.resText.text = noti.object as! String;
        }
    }
    
    func initLogProducer() {
        
        let utils = DemoUtils.shared
         let config = ClsLogSenderConfig(
             endpoint: "ap-guangzhou.cls.tencentcs.com" ?? "",
             accessKeyId: "" ?? "",
             accessKey: "" ?? ""
         )
         sender = LogSender.shared()
         sender.setConfig(config)
         sender.start()
    }
    
    func AlertInfo(str :String){
        let alert = UIAlertController(title: "弹窗", message: str, preferredStyle: .alert)
                let ok = UIAlertAction(title: "OK", style: .default)
                alert.addAction(ok)
                self.present(alert, animated: true, completion: nil)
    }
    
    @IBAction func SendLog(_ sender: UIButton) {
        for i in 0..<1 {
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
            ClsLogStorage.sharedInstance().write(logItem, topicId: "topicid")
             { success, error in
                if success {
                    print("日志写入成功（第 \(i + 1) 条），等待发送")
                } else {
                    print("日志写入失败（第 \(i + 1) 条），error: \(error.debugDescription)")
                }
            }
        }
    }
    @IBAction func DestroyProducer(_ sender: UIButton) {
        AlertInfo(str: "Producer开始销毁")
        client.destroyClsLogProducer()
    }
    
    
    func getOneLog() -> ClsLog {
        let log = ClsLog()
        log.putClsContent("content_key_1", value:"1abcakjfhksfsfsxyz012345678!@#$%^&*()_+")
        log.putClsContent("content_key_2", value:"2abcdefghijklmnopqrstuvwxyz4444444!@#$%^&*()_+")
        log.putClsContent("content_key_3", value:"3slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putClsContent("content_key_4", value:"4slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putClsContent("content_key_5", value:"5slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putClsContent("content_key_6", value:"6slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putClsContent("content_key_7", value:"7slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putClsContent("content_key_8", value:"8slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putClsContent("content_key_9", value:"9abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+")
        log.putClsContent("content", value:"中文")
        return log
    }
}

