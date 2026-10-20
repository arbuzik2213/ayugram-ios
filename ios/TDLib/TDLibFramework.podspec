# Локальный pod с готовой сборкой TDLib (https://github.com/Swiftgram/TDLibFramework).
# Сам TDLibFramework.xcframework скачивается скриптом scripts/fetch_tdlib.sh
Pod::Spec.new do |s|
  s.name             = 'TDLibFramework'
  s.version          = '1.8.68'
  s.summary          = 'Prebuilt TDLib for iOS'
  s.homepage         = 'https://github.com/Swiftgram/TDLibFramework'
  s.license          = { :type => 'BSL-1.0' }
  s.author           = 'Swiftgram'
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.vendored_frameworks = 'TDLibFramework.xcframework'
  s.libraries        = 'c++', 'z'
end
