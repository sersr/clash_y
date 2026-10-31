Pod::Spec.new do |s|
  s.name             = 'clash_service'
  s.version          = '0.0.1'
  s.summary          = 'Platform service lifecycle for Clashy.'
  s.description      = 'iOS Network Extension management for the Clashy VPN service.'
  s.homepage         = 'https://github.com/sersr/clash_y'
  s.author           = { 'sersr' => 'https://github.com/sersr' }
  s.source           = { :path => '.' }
  s.ios.deployment_target = '15.0'
  s.swift_version    = '5.0'
  s.source_files     = 'clash_service/Sources/clash_service/**/*.swift'
  s.frameworks       = 'NetworkExtension'
  s.dependency 'Flutter'
end
