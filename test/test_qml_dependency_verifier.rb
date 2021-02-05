# frozen_string_literal: true
require 'fileutils'
require 'vcr'

require_relative '../lib/qml_dependency_verifier'
require_relative 'lib/testcase'

require 'mocha/test_unit'

# Test qml dep verifier
class QMLDependencyVerifierTest < TestCase
  def const_reset(klass, symbol, obj)
    klass.send(:remove_const, symbol)
    klass.const_set(symbol, obj)
  end

  def setup
    VCR.configure do |config|
      config.cassette_library_dir = datadir
      config.hook_into :webmock
    end
    VCR.insert_cassette(File.basename(__FILE__, '.rb'))

    Dir.chdir(datadir)

    Apt::Repository.send(:reset)
    # Disable automatic update
    Apt::Abstrapt.send(:instance_variable_set, :@last_update, Time.now)

    reset_child_status! # Make sure $? is fine before we start!

    # Let all backtick or system calls that are not expected fall into
    # an error trap!
    Object.any_instance.expects(:`).never
    Object.any_instance.expects(:system).never

    # Default stub architecture as amd64
    Object.any_instance.stubs(:`)
          .with('dpkg-architecture -qDEB_HOST_ARCH')
          .returns('amd64')

    # We'll temporary mark packages as !auto, mock this entire thing as we'll
    # not need this for testing.
    Apt::Mark.stubs(:tmpmark).yields
  end

  def teardown
    VCR.eject_cassette(File.basename(__FILE__, '.rb'))
    QML::StaticMap.reset!
  end

  def data(path = nil)
    index = 0
    caller = ''
    until caller.start_with?('test_')
      caller = caller_locations(index, 1)[0].label
      index += 1
    end
    File.join(*[datadir, caller, path].compact)
  end

  def ref_path
    "#{data}.ref"
  end

  def ref
    JSON.parse(File.read(ref_path))
  end

  def test_missing_modules
    # Make sure our ignore is in place in the data dir.

    QML::StaticMap.data_file = File.join(data, 'static.yaml')

    # NB: this testcase is chdir in the datadir not the @tmpdir!
    assert(File.exist?('packaging/debian/plasma-widgets-addons.qml-ignore'))
    # Prepare sequences, divert search path and run verification.
    const_reset(QML, :SEARCH_PATHS, [File.join(data, 'qml')])

    system_sequence = sequence('system')
    list_sequence = sequence('dpkglist')
    JSON.parse(File.read(data('system_sequence'))).each do |cmd|
      Object.any_instance.expects(:system)
            .with(*cmd)
            .returns(true)
            .in_sequence(system_sequence)
    end
    JSON.parse(File.read(data('list_sequence'))).each do |cmd|
      DPKG.stubs(:list).with(*cmd).returns([])
    end
    DPKG.stubs(:list)
        .with('plasma-widgets-addons')
        .returns([data('main.qml')])
    # org.plasma.configuration is static mapped to plasma-framework, so we
    # need this call to happen to check if it installed.
    # this must not ever be removed!
    Object.any_instance.stubs(:system)
          .with('dpkg -s plasma-framework 2>&1 > /dev/null')
          .returns(true)

    repo = mock('repo')
    repo.stubs(:add).returns(true)
    repo.stubs(:remove).returns(true)
    repo.stubs(:binaries).returns('kwin-addons' => '4:5.2.1+git20150316.1204+15.04-0ubuntu0', 'plasma-dataengines-addons' => '4:5.2.1+git20150316.1204+15.04-0ubuntu0', 'plasma-runners-addons' => '4:5.2.1+git20150316.1204+15.04-0ubuntu0', 'plasma-wallpapers-addons' => '4:5.2.1+git20150316.1204+15.04-0ubuntu0', 'plasma-widget-kimpanel' => '4:5.2.1+git20150316.1204+15.04-0ubuntu0', 'plasma-widgets-addons' => '4:5.2.1+git20150316.1204+15.04-0ubuntu0', 'kdeplasma-addons-data' => '4:5.2.1+git20150316.1204+15.04-0ubuntu0')

    missing = QMLDependencyVerifier.new(repo).missing_modules
    assert_equal(1, missing.size, 'More things missing than expected' \
                                  " #{missing}")

    assert(missing.key?('plasma-widgets-addons'))
    missing = missing.fetch('plasma-widgets-addons')
    assert_equal(1, missing.size, 'More modules missing than expected' \
                 " #{missing}")

    missing = missing.first
    assert_equal('QtWebKit', missing.identifier)
  end

  def test_log_no_missing
    repo = mock('repo')
    QMLDependencyVerifier.new(repo).send(:log_missing, {})
  end

  def test_static_which_isnt_static
    # When a package was c++ runtime-injected at some point we would have
    # added it to the static map. If it later turns into a proper module
    # we need to undo the static mapping. Otherwise the dependency expectation
    # can be royally wrong as a regular package would be in qml-module-foo,
    # a runtime-injected one in any random package.

    QML::StaticMap.data_file = File.join(data, 'static.yaml')

    const_reset(QML, :SEARCH_PATHS, [File.join(data, 'qml')])

    system_sequence = sequence('system')
    Object.any_instance.expects(:system)
          .with('apt-get', '-y', '-o', 'APT::Get::force-yes=true', '-o', 'Debug::pkgProblemResolver=true', '-q', 'install', 'kwin-addons=4:5.2.1+git20150316.1204+15.04-0ubuntu0')
          .returns(true)
          .in_sequence(system_sequence)
    Object.any_instance.expects(:system)
          .with('apt-get', '-y', '-o', 'APT::Get::force-yes=true', '-o', 'Debug::pkgProblemResolver=true', '-q', '--purge', 'autoremove')
          .returns(true)
          .in_sequence(system_sequence)

    # DPKG.stubs(:list).returns([])
    DPKG.stubs(:list).with('kwin-addons')
        .returns([data('main.qml')])

    repo = mock('repo')
    repo.stubs(:add).returns(true)
    repo.stubs(:remove).returns(true)
    repo.stubs(:binaries).returns('kwin-addons' => '4:5.2.1+git20150316.1204+15.04-0ubuntu0')

    assert_raises QML::Module::ExistingStaticError do
      QMLDependencyVerifier.new(repo).missing_modules
    end
  end
end
