Pod::Spec.new do |s|
  s.name         = "stay22_flutter"
  s.version      = "1.2.0"
  s.summary      = "Stay22 SDK for Flutter"
  s.description  = <<-DESC
    Turns explicit travel intent into a single, well-timed local notification
    that opens a Stay22 accommodation booking page.
  DESC
  s.homepage     = "https://www.stay22.com"
  s.license      = { :type => "Commercial", :file => "../LICENSE" }
  s.author       = { "Stay22" => "support@stay22.com" }
  # Tagged with the bare version in the distribution repo, matching how
  # stay22-ios-sdk and stay22-android-sdk tag their own releases.
  s.source       = { :git => "https://github.com/Stay22/stay22-flutter-sdk.git", :tag => "#{s.version}" }

  s.platform      = :ios, "15.0"
  s.swift_version = "5.9"

  s.source_files = "Classes/**/*.swift"
  s.dependency "Flutter"

  # The SDK ships as a binary. It is vendored into this package (see
  # scripts/sync-binaries.sh) rather than fetched from a pod, because Stay22
  # publishes no CocoaPod — the previous `s.dependency "Stay22SDK"` here could
  # never resolve.
  s.vendored_frameworks = "Frameworks/Stay22SDK.xcframework"

  # Deliberately NOT `s.static_framework = true`. Flutter's Podfile template
  # already declares `use_frameworks!`, and that flag describes how *this* pod
  # builds — setting it while vendoring a dynamic (mh_dylib) framework is a
  # known route to duplicate-symbol and missing-embed failures. CocoaPods
  # embeds and re-signs a vendored dynamic framework on its own.
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
    # Neither Flutter.framework nor Stay22SDK ships an i386 slice.
    "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "i386",
  }
end
