#
# Be sure to run `pod lib lint MembraneRTC.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'MembraneRTC'
  s.summary          = 'Membrane WebRTC client fully compatible with `Membrane RTC Engine` for iOS.'
  s.homepage         = 'https://github.com/membraneframework/membrane-webrtc-ios'
  s.version = '5.3.0'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Software Mansion' => 'https://swmansion.com' }
  s.source           = { :git => 'https://github.com/incubo4u/membrane-webrtc-ios.git', :branch => 'master' }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  s.source_files = 'Sources/MembraneRTC/**/*'
  s.dependency 'WebRTC-SDK', '104.5112.15'
  s.dependency 'SwiftProtobuf'
  s.dependency 'PromisesSwift'
  s.dependency 'SwiftPhoenixClient', '~> 4.0.0'
  s.dependency 'SwiftLogJellyfish', '1.5.2'
  s.pod_target_xcconfig = { 'ENABLE_BITCODE' => 'NO' }

  s.subspec "Broadcast" do |spec|
    spec.source_files = "Sources/MembraneRTC/Media/BroadcastSampleSource.swift", "Sources/MembraneRTC/IPC/**/*.{h,m,mm,swift}"
  end
end
