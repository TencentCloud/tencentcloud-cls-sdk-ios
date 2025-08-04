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
        
        let config = ClsLogProducerConfig(clsWithCoreInfo:utils.endpoint, accessKeyID:utils.accessKeyId, accessKeySecret:utils.accessKeySecret)!
        config.setClsTopic(utils.topic)
        config.setClsPackageLogBytes(1024*1024)
        config.setClsPackageLogCount(1024)
        config.setClsPackageTimeout(3000)
        config.setClsMaxBufferLimit(64*1024*1024)
        config.setClsSendThreadCount(1)
        config.setClsConnectTimeoutSec(10)
        config.setClsSendTimeoutSec(10)
        config.setClsDestroyFlusherWaitSec(1)
        config.setClsDestroySenderWaitSec(1)
        config.setClsCompressType(1)
        let tv = self.resText;

        let callbackFunc: ClsSendCallBackFunc =  {config_name,result,log_bytes,compressed_bytes,req_id,error_message,raw_buffer,user_param in
            let res = ClsLogProducerResult(rawValue: Int(result))
            let reqId = req_id == nil ? "":String(cString: req_id!)
            let topic_id = config_name == nil ? "":String(cString: config_name!)
            if(result == CLS_LOG_PRODUCER_OK){
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
            self.client = ClsLogProducerClient(clsLogProducer:config, callback:callbackFunc)
    }
    
    func AlertInfo(str :String){
        let alert = UIAlertController(title: "弹窗", message: str, preferredStyle: .alert)
                let ok = UIAlertAction(title: "OK", style: .default)
                alert.addAction(ok)
                self.present(alert, animated: true, completion: nil)
    }
    
    @IBAction func SendLog(_ sender: UIButton) {
        let log = getOneLog()
        let res = client?.post(log)
        if(res?.rawValue == 0){
            AlertInfo(str: "消息已经发送，参考回调通知")
        }else if(res?.rawValue == 1){
            AlertInfo(str: "Producer已经销毁，不能发送log")
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

