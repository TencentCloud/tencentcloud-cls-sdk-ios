#
#  Be sure to run `pod s lint TencentCloudLogProducer.podspec' to ensure this is a
#  valid s and to remove all comments including this before submitting the s.
#
#  To learn more about Podspec attributes see https://guides.cocoapods.org/syntax/podspec.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|
  s.name         = "TencentCloudLogProducer"
  s.version      = "1.1.3"
  s.summary      = "TencentCloudLogProducer ios"
  s.description  = <<-DESC
  log service ios producer.
  https://cloud.tencent.com/product/cls
                   DESC

  s.homepage     = 'https://cloud.tencent.com/'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author             = { "herrylv" => "herrylv@tencent.com" }
  s.source       = { :git => "https://github.com/TencentCloud/tencentcloud-cls-sdk-ios.git", :tag => s.version.to_s  }
  s.social_media_url = 'http://t.cn/AiRpol8C'
  s.ios.deployment_target = '9.0'
  s.default_subspec = 'Core'
  s.static_framework = true
  s.pod_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
  s.subspec 'Core' do |c|
      c.vendored_libraries = 'TencentCloudLogProducer/tencentCloud-log-c-sdk/curl/lib/libcurl.a'
      c.source_files =
          'TencentCloudLogProducer/TencentCloudLogProducer/*.{h,m}',
          'TencentCloudLogProducer/tencentCloud-log-c-sdk/src/*.{c,h}',
          'TencentCloudLogProducer/tencentCloud-log-c-sdk/curl/include/curl/*.{c,h}',
          'TencentCloudLogProducer/TencentCloudLogProducer/utils/*.{m,h}'
    
          c.public_header_files =
          'TencentCloudLogProducer/TencentCloudLogProducer/*.h',
          'TencentCloudLogProducer/TencentCloudLogProducer/utils/*.h',
          'TencentCloudLogProducer/tencentCloud-log-c-sdk/src/log_define.h',
          'TencentCloudLogProducer/tencentCloud-log-c-sdk/src/log_adaptor.h',
          'TencentCloudLogProducer/tencentCloud-log-c-sdk/src/log_inner_include.h',
          'TencentCloudLogProducer/tencentCloud-log-c-sdk/src/log_multi_thread.h',
          'TencentCloudLogProducer/tencentCloud-log-c-sdk/src/log_producer_client.h',
          'TencentCloudLogProducer/tencentCloud-log-c-sdk/src/log_error.h',
          'TencentCloudLogProducer/tencentCloud-log-c-sdk/src/ProducerConfig.h',
          'TencentCloudLogProducer/tencentCloud-log-c-sdk/src/log_producer_config.h'
          
          c.dependency 'GMOpenSSL', '~> 2.2.6'
  s.resource_bundles = { s.name => ['TencentCloudLogProducer/TencentCloudLogProducer/PrivacyInfo.xcprivacy'] }
  end
  s.subspec 'NetWorkDiagnosis' do |b|
      b.dependency 'TencentCloudLogProducer/Core'
      b.source_files =
      'TencentCloudLogProducer/TencentCloudLogProducer/NetWorkDiagnosis/*.{m,h}'
      b.public_header_files =
      'TencentCloudLogProducer/TencentCloudLogProducer/NetWorkDiagnosis/*.h',
      b.frameworks = "SystemConfiguration"
      b.dependency 'Reachability', '~> 3.2'
      b.libraries = 'resolv'
  end
end
