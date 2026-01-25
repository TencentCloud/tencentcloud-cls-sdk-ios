//
//  MainViewController.swift
//  TencentCloudLogSwiftDemo
//
//  参照OC版本的 MainViewController 实现
//  主界面，显示各个功能入口按钮

import UIKit

class MainViewController: BaseViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "CLS iOS Demo"
        
        // 设置导航栏样式
        navigationController?.navigationBar.backgroundColor = UIColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0)
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor.white
        ]
        navigationItem.backBarButtonItem = UIBarButtonItem(
            title: "返回",
            style: .plain,
            target: nil,
            action: nil
        )
        
        initViews()
    }
    
    private func initViews() {
        view.backgroundColor = .white
        
        // 创建按钮（参照OC版本的布局）
        _ = createButton(title: "基本配置", action: #selector(gotoGeneralPage), x: 0, y: 0)
        
        _ = createButton(
            title: "销毁配置",
            action: #selector(gotoDestroyPage),
            x: BaseViewController.cellWidth + BaseViewController.padding,
            y: 0
        )
        
        _ = createButton(
            title: "网络探测",
            action: #selector(gotoNetDiaPage),
            x: (BaseViewController.cellWidth + BaseViewController.padding) * 2,
            y: 0
        )
    }
    
    // MARK: - 页面跳转
    
    @objc private func gotoGeneralPage() {
        gotoPage(controller: ProducerExampleViewController())
    }
    
    @objc private func gotoDestroyPage() {
        // TODO: 实现销毁配置页面
        let alert = UIAlertController(title: "提示", message: "销毁配置功能待实现", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func gotoNetDiaPage() {
        gotoPage(controller: NetworkDiagnosisViewController())
    }
    
    private func gotoPage(controller: UIViewController) {
        navigationController?.pushViewController(controller, animated: true)
    }
}
