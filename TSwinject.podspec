Pod::Spec.new do |s|
  s.name             = 'TSwinject'
  s.version          = '1.0.0'
  s.summary          = 'Casting-free Swinject alternative for Swift'
  s.description      = <<-DESC
    TSwinject wraps every registered instance in a generic class
    (DiEntryConcrete<T> / DiEntryWeak<T>) and resolves on those concrete generic
    types. Casting Any to a known generic class is cheap; casting to a protocol
    existential forces the runtime to walk every protocol conformance descriptor
    in the image. The public API mirrors Swinject's, so call sites migrate by
    swapping the import.
  DESC

  s.homepage = 'https://github.com/ChrisBenua/TSwinject'
  s.author   = 'Kristian Benua'
  s.license  = { type: 'MIT', file: 'LICENSE' }
  s.source   = { git: 'https://github.com/ChrisBenua/TSwinject.git', tag: s.version.to_s }

  s.swift_version         = '6.0'
  s.ios.deployment_target = '16.0'
  s.osx.deployment_target = '13.0'
  s.static_framework      = true

  s.source_files = 'Sources/TSwinject/**/*.swift'

  s.pod_target_xcconfig = {
    'EXCLUDED_SOURCE_FILE_NAMES'      => '*-dummy.m',
    'SWIFT_REFLECTION_METADATA_LEVEL' => 'none',
    'SWIFT_OPTIMIZATION_LEVEL'        => '-Osize',
    'SWIFT_COMPILATION_MODE'          => 'wholemodule',
    'OTHER_SWIFT_FLAGS'               => '$(inherited) -Xfrontend -internalize-at-link'
  }

  s.test_spec 'UnitTests' do |t|
    t.source_files = 'Tests/TSwinjectTests/**/*.swift'
  end

  # Run in Release or the numbers are noise.
  s.test_spec 'Benchmarks' do |t|
    t.source_files = 'Tests/TSwinjectBenchmarks/**/*.swift'
    t.dependency 'Swinject', '~> 2.9'
    t.pod_target_xcconfig = {
      'SWIFT_OPTIMIZATION_LEVEL' => '-O',
      'SWIFT_COMPILATION_MODE'   => 'wholemodule'
    }
  end
end
