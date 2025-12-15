Pod::Spec.new do |s|
  s.name         = "TencentCloudLogProducer"
  s.version      = "2.0.0"
  s.summary      = "TencentCloudLogProducer ios"
  s.description  = <<-DESC
  log service ios producer.
  https://cloud.tencent.com/product/cls
                   DESC

  s.homepage     = 'https://cloud.tencent.com/'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = { "herrylv" => "herrylv@tencent.com" }
  s.source       = { :git => "https://github.com/TencentCloud/tencentcloud-cls-sdk-ios.git", :tag => s.version.to_s  }
  s.social_media_url = 'https://cloud.tencent.com/document/product/614/67157'
  s.ios.deployment_target = '10.0'
  s.default_subspec = 'Core'
  s.static_framework = true
  s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }

  # Core子spec：明确系统依赖，方便NetWorkDiagnosis继承
  s.subspec 'Core' do |c|
      c.source_files = 'TencentCloudLogProducer/Core/*.{h,m}'
      c.public_header_files = 'TencentCloudLogProducer/Core/*.h'
      
      # Core核心依赖（NetWorkDiagnosis会自动继承）
      c.dependency 'Protobuf', '~> 3.29.5'
      c.dependency 'FMDB', '~> 2.7.5'
      c.dependency 'Reachability', '~> 3.2'
      
      # Core必需的系统库/框架（NetWorkDiagnosis需复用）
      c.libraries = 'z', 'sqlite3' # FMDB依赖sqlite3，Protobuf依赖zlib
      c.frameworks = 'Foundation', 'SystemConfiguration', 'UIKit' # 基础框架
      
      # 资源文件归属Core，NetWorkDiagnosis自动可访问
      c.resource_bundles = { s.name => ['TencentCloudLogProducer/PrivacyInfo.xcprivacy'] }
  end

  # NetWorkDiagnosis子spec：补充Core未覆盖的依赖，复用Core的基础依赖
  s.subspec 'NetWorkDiagnosis' do |b|
      b.dependency 'TencentCloudLogProducer/Core' # 自动继承Core的所有依赖
      
      b.source_files = 'TencentCloudLogProducer/NetWorkDiagnosis/*.{m,h}'
      b.public_header_files = 'TencentCloudLogProducer/NetWorkDiagnosis/*.h'
      
      # 1. 网络诊断专属框架（Core未包含）
      b.frameworks = "CoreTelephony" # 运营商信息获取
      # 2. 网络诊断专属系统库（Core未包含）
      b.libraries = 'resolv' # DNS解析依赖
      # 3. 宏定义（不影响Core，仅网络诊断使用）
      b.pod_target_xcconfig = {
        'GCC_PREPROCESSOR_DEFINITIONS' => 'CLS_HAS_CORE_TELEPHONY=1'
      }
  end
end
