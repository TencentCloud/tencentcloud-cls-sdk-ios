//
//  BaseViewController.swift
//  TencentCloudLogSwiftDemo
//
//  参照OC版本的 ViewController 基类
//  提供通用的UI创建方法

import UIKit

class BaseViewController: UIViewController {
    
    // MARK: - 常量定义（参照 PrefixHeader.pch）
    
    static let screenWidth = UIScreen.main.bounds.width
    static let screenHeight = UIScreen.main.bounds.height
    static let padding: CGFloat = 12
    static let cellWidth = (screenWidth - padding * 4) / 3
    static let cellHeight: CGFloat = 40
    
    static var isIPhoneX: Bool {
        return screenWidth >= 375.0 && screenHeight >= 812.0
    }
    
    static var navBarAndStatusBarHeight: CGFloat {
        return isIPhoneX ? 88.0 : 64.0
    }
    
    // MARK: - 创建按钮
    
    func createButton(title: String, action: Selector, x: CGFloat, y: CGFloat) -> UIButton {
        return createButton(
            title: title,
            action: action,
            x: x,
            y: y,
            width: BaseViewController.cellWidth,
            height: BaseViewController.cellHeight
        )
    }
    
    func createButton(title: String, action: Selector, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> UIButton {
        let button = UIButton(frame: CGRect(
            x: BaseViewController.padding + x,
            y: BaseViewController.navBarAndStatusBarHeight + BaseViewController.padding * 2 + y,
            width: width,
            height: height
        ))
        button.backgroundColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        button.layer.cornerRadius = 4
        button.addTarget(self, action: action, for: .touchUpInside)
        button.setTitle(title, for: .normal)
        
        view.addSubview(button)
        
        return button
    }
    
    // MARK: - 创建标签
    
    func createLabel(title: String, x: CGFloat, y: CGFloat) -> UILabel {
        return createLabel(
            title: title,
            x: x,
            y: y,
            width: BaseViewController.cellWidth,
            height: BaseViewController.cellHeight
        )
    }
    
    func createLabel(title: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> UILabel {
        let label = UILabel(frame: CGRect(
            x: BaseViewController.padding + x,
            y: BaseViewController.navBarAndStatusBarHeight + BaseViewController.padding * 2 + y,
            width: width,
            height: height
        ))
        label.backgroundColor = .white
        label.textColor = .black
        label.text = title
        
        view.addSubview(label)
        
        return label
    }
    
    // MARK: - 创建文本视图
    
    func createTextView(text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> UITextView {
        let textView = UITextView(frame: CGRect(
            x: BaseViewController.padding + x,
            y: BaseViewController.navBarAndStatusBarHeight + BaseViewController.padding * 2 + y,
            width: width,
            height: height
        ))
        textView.backgroundColor = .white
        textView.textColor = .black
        textView.text = text
        
        view.addSubview(textView)
        return textView
    }
}
