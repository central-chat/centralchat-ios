Pod::Spec.new do |spec|
  spec.name         = 'CentralChat'
  spec.version      = ENV['CENTRALCHAT_VERSION'] || '0.1.0'
  spec.summary      = 'The Central chat, embedded in your iOS app.'
  spec.description  = <<~DESC
    Three calls — init, show, hide — over the same chat bundle the website runs.
    End-to-end encryption, sync, attachments and voice messages come from one
    implementation shared with web and Android, so a chat upgrade needs no App
    Store release.
  DESC
  spec.homepage     = 'https://central.chat'
  spec.license      = { type: 'Apache-2.0', file: 'LICENSE' }
  spec.author       = { 'Central' => 'developers@central.chat' }
  # A MIRROR of this directory, not the monorepo it lives in: SwiftPM resolves
  # `Package.swift` at a repository ROOT and CocoaPods resolves source_files from
  # the podspec's directory, so neither can point into a subdirectory. The
  # release job pushes this directory there and tags it; the source of truth
  # stays here. The URL is supplied at release time rather than written down, so
  # that the repository this is developed in is never named in what ships.
  spec.source       = {
    git: ENV.fetch('CENTRALCHAT_IOS_REPO'),
    tag: spec.version.to_s,
  }

  spec.ios.deployment_target = '15.0'
  spec.swift_version = '5.9'
  spec.source_files = 'Sources/CentralChat/**/*.swift'
  spec.frameworks = 'WebKit', 'UIKit'

  # Nothing else. A chat SDK that drags in a networking stack is a chat SDK
  # somebody has to reconcile with theirs.
end
