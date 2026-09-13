Pod::Spec.new do |s|
  s.name             = 'TSwinjectMacro'
  s.version          = '1.0.0'
  s.summary          = 'Freestanding #implements macro generating TSwinject protocol-forwarding registrations'
  s.description      = <<-DESC
    #implements(container, Base.self, ProtocolA.self, ProtocolB.self) expands to
    one .transient forwarding registration per protocol, each resolving the base
    concrete type. Register the concrete type by hand with its real factory, then
    let the macro generate the protocol forwarders.
  DESC

  s.homepage = 'https://github.com/ChrisBenua/TSwinject'
  s.author   = 'Kristian Benua'
  s.license  = { type: 'MIT', file: 'LICENSE' }
  s.source   = { git: 'https://github.com/ChrisBenua/TSwinject.git', tag: s.version.to_s }

  s.swift_version         = '6.0'
  s.ios.deployment_target = '16.0'
  s.osx.deployment_target = '13.0'
  s.static_framework      = true
  s.module_map            = false
  s.prefix_header_file    = false

  # Only the macro *declaration* ships as source. The plugin is a macOS host
  # executable built by prepare_command below.
  s.source_files   = 'Sources/TSwinjectMacro/**/*.swift'
  s.preserve_paths = ['bin/TSwinjectMacroPlugin']

  s.dependency 'TSwinject', '~> 1.0'

  plugin_flag = '-load-plugin-executable ' \
    '$(PODS_TARGET_SRCROOT)/bin/TSwinjectMacroPlugin#TSwinjectMacroPlugin'

  s.pod_target_xcconfig = {
    'EXCLUDED_SOURCE_FILE_NAMES'      => '*-dummy.m',
    'SWIFT_REFLECTION_METADATA_LEVEL' => 'none',
    'SWIFT_OPTIMIZATION_LEVEL'        => '-Osize',
    'OTHER_SWIFT_FLAGS'               => "$(inherited) -Xfrontend -internalize-at-link #{plugin_flag}"
  }

  # NOTE for consumers: CocoaPods does not propagate -load-plugin-executable to
  # your targets. Any target that *writes* #implements(...) must add this to its
  # own OTHER_SWIFT_FLAGS (note PODS_ROOT, not PODS_TARGET_SRCROOT):
  #
  #   -load-plugin-executable $(PODS_ROOT)/TSwinjectMacro/bin/TSwinjectMacroPlugin#TSwinjectMacroPlugin

  s.test_spec 'Tests' do |t|
    t.source_files = 'Tests/TSwinjectMacroTests/MacroRuntimeTests.swift'
    t.pod_target_xcconfig = {
      'OTHER_SWIFT_FLAGS' => "$(inherited) #{plugin_flag}"
    }
  end

  s.app_spec 'Example' do |e|
    e.source_files = 'Example/MacroExample/**/*.swift'
    e.resources    = 'Example/MacroExample/**/*.{xib,storyboard,strings,stringsdict,xcassets,json}'
    e.info_plist = {
      'CFBundleDevelopmentRegion'  => 'en',
      'CFBundleShortVersionString' => s.version.to_s,
      'UILaunchStoryboardName'     => 'LaunchScreen'
    }
    e.pod_target_xcconfig = {
      'PRODUCT_BUNDLE_IDENTIFIER' => 'com.github.chrisbenua.tswinject.example',
      'OTHER_SWIFT_FLAGS'         => "$(inherited) #{plugin_flag}"
    }
  end

  # Builds the macro plugin, a macOS executable loaded by the Swift compiler.
  #
  # Built here rather than vendored as a binary, which means it is always native
  # to the machine running `pod install` — no universal binary needed, and no
  # checked-in blob. Budget roughly three minutes on a cold install: swift-syntax
  # is compiled in release. It is cached afterwards.
  #
  # `--target TSwinjectMacro` (not `--product`, and not the plugin target's own
  # name — neither is addressable) builds the macro library and, with it, the
  # plugin executable it depends on.
  #
  # `xcrun` pins the build to the active DEVELOPER_DIR. The plugin must be built
  # by the same toolchain that will load it, or the compiler rejects it — so do
  # not switch Xcode versions between `pod install` and `xcodebuild`.
  #
  # The scratch path is explicit and removed afterwards because building the root
  # package resolves swift-syntax *and* Swinject; several hundred MB of build
  # products would otherwise be left inside Pods/TSwinjectMacro.
  swift_flags = %w[
    -c release
    --target TSwinjectMacro
    -Xlinker -dead_strip
    -Xswiftc -Xfrontend -Xswiftc -internalize-at-link
    -Xswiftc -Xfrontend -Xswiftc -disable-reflection-metadata
  ].join(' ')

  s.prepare_command = <<~CMD
    set -euo pipefail
    mkdir -p bin
    xcrun swift build #{swift_flags} --scratch-path .macro-build
    BIN_PATH=$(xcrun swift build #{swift_flags} --scratch-path .macro-build --show-bin-path)
    cp "$BIN_PATH/TSwinjectMacroPlugin-tool" bin/TSwinjectMacroPlugin
    strip -x bin/TSwinjectMacroPlugin
    rm -rf .macro-build
  CMD
end
