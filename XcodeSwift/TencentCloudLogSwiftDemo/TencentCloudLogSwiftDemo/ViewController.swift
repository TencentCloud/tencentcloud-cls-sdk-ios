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
    fileprivate var client:     LogProducerClient!
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
        
        let config = LogProducerConfig(coreInfo:utils.endpoint, accessKeyID:utils.accessKeyId, accessKeySecret:utils.accessKeySecret)!
        config.setTopic(utils.topic)
        config.setPackageLogBytes(1024*1024)
        config.setPackageLogCount(1024)
        config.setPackageTimeout(3000)
        config.setMaxBufferLimit(64*1024*1024)
        config.setSendThreadCount(1)
        config.setConnectTimeoutSec(10)
        config.setSendTimeoutSec(10)
        config.setDestroyFlusherWaitSec(1)
        config.setDestroySenderWaitSec(1)
        config.setCompressType(1)
        let tv = self.resText;

        let callbackFunc: SendCallBackFunc =  {config_name,result,log_bytes,compressed_bytes,req_id,error_message,raw_buffer,user_param in
            let res = LogProducerResult(rawValue: Int(result))
            let reqId = req_id == nil ? "":String(cString: req_id!)
            let topic_id = config_name == nil ? "":String(cString: config_name!)
            if(result == LOG_PRODUCER_OK){
                let success = "send success, topic :\(topic_id), result : \(result), log bytes : \(log_bytes), compressed bytes : \(compressed_bytes), request id : \(reqId)"
                print(success)
                NotificationCenter.default.post(name: Notification.Name(rawValue: "test"), object: success);
//                self.resText.text = success
            }else{
                let fail = "send fail, topic :\(topic_id), result : \(result), log bytes : \(log_bytes), compressed bytes : \(compressed_bytes), request id : \(reqId)"
                print(fail)
                NotificationCenter.default.post(name: Notification.Name(rawValue: "test"), object: fail);
            }
        }
            self.client = LogProducerClient(clsLogProducer:config, callback:callbackFunc)
    }
    
    func AlertInfo(str :String){
        let alert = UIAlertController(title: "弹窗", message: str, preferredStyle: .alert)
                let ok = UIAlertAction(title: "OK", style: .default)
                alert.addAction(ok)
                self.present(alert, animated: true, completion: nil)
    }
    
    @IBAction func SendLog(_ sender: UIButton) {
        let log = getOneLog()
        let res = client?.post(log, flush: 1)
        if(res?.rawValue == 0){
            AlertInfo(str: "消息已经发送，参考回调通知")
        }else if(res?.rawValue == 1){
            AlertInfo(str: "Producer已经销毁，不能发送log")
        }
    }
    @IBAction func DestroyProducer(_ sender: UIButton) {
        AlertInfo(str: "Producer开始销毁")
        client.destroyLogProducer()
    }
    
    
    func getOneLog() -> Log {
        let log = Log()
        log.putContent("content_key_1", value:"1abcakjfhksfsfsxyz012345678!@#$%^&*()_+")
        log.putContent("content_key_2", value:"2abcdefghijklmnopqrstuvwxyz4444444!@#$%^&*()_+")
        log.putContent("content_key_3", value:"3slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putContent("content_key_4", value:"4slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putContent("content_key_5", value:"5slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putContent("content_key_6", value:"6slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putContent("content_key_7", value:"7slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putContent("content_key_8", value:"8slfjhdfjh092834932hjksnfjknskjfnd!@#$%^&*()_+")
        log.putContent("content_key_9", value:"9abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+")
        log.putContent("content", value:"中文")
        return log
    }
}

