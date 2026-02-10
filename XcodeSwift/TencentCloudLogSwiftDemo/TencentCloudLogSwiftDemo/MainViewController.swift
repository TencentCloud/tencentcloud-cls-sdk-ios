//
//  MainViewController.swift
//  TencentCloudLogSwiftDemo
//
//  Created by CLS Team on 2025/02/09.
//

import UIKit

class MainViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        title = "CLS iOS SDK"
        
        setupUI()
    }
    
    private func setupUI() {
        // 日志上传按钮
        let logUploadBtn = UIButton(type: .system)
        logUploadBtn.frame = CGRect(x: 50, y: 150, width: view.bounds.width - 100, height: 50)
        logUploadBtn.setTitle("日志上传", for: .normal)
        logUploadBtn.setTitleColor(.black, for: .normal)
        logUploadBtn.addTarget(self, action: #selector(logUploadBtnClick), for: .touchUpInside)
        view.addSubview(logUploadBtn)
        
        // 网络探测按钮
        let networkDetectBtn = UIButton(type: .system)
        networkDetectBtn.frame = CGRect(x: 50, y: 250, width: view.bounds.width - 100, height: 50)
        networkDetectBtn.setTitle("网络探测", for: .normal)
        networkDetectBtn.setTitleColor(.black, for: .normal)
        networkDetectBtn.addTarget(self, action: #selector(networkDetectBtnClick), for: .touchUpInside)
        view.addSubview(networkDetectBtn)
    }
    
    @objc private func logUploadBtnClick() {
        let logVC = LogUploadViewController()
        navigationController?.pushViewController(logVC, animated: true)
    }
    
    @objc private func networkDetectBtnClick() {
        let networkVC = NetworkDetectViewController()
        navigationController?.pushViewController(networkVC, animated: true)
    }
}
