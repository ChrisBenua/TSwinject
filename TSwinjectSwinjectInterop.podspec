Pod::Spec.new do |s|
  s.name             = 'TSwinjectSwinjectInterop'
  s.version          = '1.0.0'
  s.summary          = 'Migration bridge between TSwinject and Swinject'
  s.description      = <<-DESC
    Optional interop layer for gradual migration from Swinject to TSwinject.
    Container.attachSwinjectBridge(_:scopeMap:) turns a TSwinject container into
    a typed facade over a real Swinject container - one shared registry, so
    migrated and unmigrated code see the same registrations. Drop this pod once
    migration is complete and the Swinject dependency goes with it.
  DESC

  s.homepage = 'https://github.com/ChrisBenua/TSwinject'
  s.author   = 'Kristian Benua'
  s.license  = { type: 'MIT', file: 'LICENSE' }
  s.source   = { git: 'https://github.com/ChrisBenua/TSwinject.git', tag: s.version.to_s }

  s.swift_version         = '6.0'
  s.ios.deployment_target = '16.0'
  s.osx.deployment_target = '13.0'
  s.static_framework      = true

  s.source_files = 'Sources/TSwinjectSwinjectInterop/**/*.swift'

  s.dependency 'TSwinject', '~> 1.0'
  s.dependency 'Swinject', '~> 2.9'

  s.pod_target_xcconfig = {
    'EXCLUDED_SOURCE_FILE_NAMES'      => '*-dummy.m',
    'SWIFT_REFLECTION_METADATA_LEVEL' => 'none',
    'SWIFT_OPTIMIZATION_LEVEL'        => '-Osize',
    'SWIFT_COMPILATION_MODE'          => 'wholemodule',
    # Add -DSWINJECT_2_10_AVAILABLE to enable the per-type resetObjectScope
    # mirroring, which requires Swinject 2.10.0 or newer.
    'OTHER_SWIFT_FLAGS'               => '$(inherited) -Xfrontend -internalize-at-link'
  }

  s.test_spec 'UnitTests' do |t|
    t.source_files = 'Tests/TSwinjectInteropTests/**/*.swift'
  end
end
