# frozen_string_literal: true
# SPDX-License-Identifier: LGPL-2.1-only OR LGPL-3.0-only OR LicenseRef-KDE-Accepted-LGPL
# SPDX-FileCopyrightText: 2014-2021 Harald Sitter <sitter@kde.org>

require 'test/unit'

require 'tmpdir'
require 'webmock/test_unit'
require 'net/smtp'
require 'mocha/test_unit'
require 'objspace'

require_relative 'assert_xml'

# Deal with a require-time expecation here. docker.rb does a version coercion
# hack at require-time which will hit the socket. As we install webmock above
# already it may be active by the time docker.rb is required, making it
# necessary to stub the expecation.
WebMock.stub_request(:get, 'http://unix/v1.16/version')
       .to_return(body: '{"Version":"17.03.0-ce","ApiVersion":"1.26","MinAPIVersion":"1.12"}')

# Test case base class handling fixtures and chdirring to not pollute the source
# dir.
# This thing does a whole bunch of stuff, you'd best read through priority_setup
# and priority_teardown to get the basics. Its primary function is to
# setup/teardown common stuff we need across multiple test cases or to ensure
# pristine working conditions for each test.
# The biggest feature by far is that a TestCase is always getting an isolated
# PWD in a tmpdir. On top of that fixture loading helpers are provided in the
# form of {#data} and {#fixture_file} which grab fixtures out of
# test/data/file_name/test_method_name.
# This class is very long because it is very flexible and very complicated.
class TestCase < Test::Unit::TestCase
  include EquivalentXmlAssertations

  ATFILEFAIL = 'Could not determine the basename of the file of the' \
               ' class inheriting TestCase. Either flatten your inheritance' \
               ' graph or set the name manually using `self.file = __FILE__`' \
               ' in class scope.'

  class << self
    attr_accessor :file

    # attr_accessor :required_binaries
    def required_binaries(*args)
      @required_binaries ||= []
      @required_binaries += args.flatten
    end
  end

  def self.autodetect_inherited_file
    caller_locations.each do |call|
      next if call.label.include?('inherited')

      path = call.absolute_path
      @file = path if path.include?('/test/')
      break
    end
    raise ATFILEFAIL unless @file
  end

  def self.inherited(subclass)
    @file = nil
    super(subclass)
    subclass.autodetect_inherited_file unless @file
  end

  # Automatically issues omit() if binaries required for a test are not present
  # @param binaries [Array<String>] binaries to check for (can be full path)
  def require_binaries(*binaries)
    binaries.flatten.each do |bin|
      next if system("type #{bin} > /dev/null 2>&1")

      omit("#{self.class} requires #{bin} but #{bin} is not in $PATH")
    end
  end

  def assert_is_a(obj, expected)
    actual = obj.class.ancestors | obj.class.included_modules
    diff = AssertionMessage.delayed_diff(expected, actual)
    format = <<MSG
<?> expected but its ancestors and includes are at the very least
<?>.?
MSG
    message = build_message(message, format, expected, actual, diff)
    assert_block(message) { obj.is_a?(expected) }
  end

  def priority_setup
    raise ATFILEFAIL unless self.class.file

    # Remove some CI vars to ensure tests are self-sufficient (i.e. passing outside CI envs)
    ENV.delete('WORKSPACE')
    ENV.delete('BUILD_NUMBER')

    script_base_path = File.expand_path(File.dirname(self.class.file))
    script_name = File.basename(self.class.file, '.rb')
    @datadir = File.join(script_base_path, 'data', script_name)
    @previous_pwd = Dir.pwd
    @tmpdir = Dir.mktmpdir(self.class.to_s.tr(':', '_'))
    Dir.chdir(@tmpdir)
    require_binaries(self.class.required_binaries)

    # Keep copy of env to restore in teardown. Note that clone wouldn't actually
    # copy the underlying data as that is not stored in the ENV. Instead we'll
    # need to convert to a hash which basically creates a "snapshot" of the
    # proc env at the time of the call.
    # NB: don't use an easily overwritten variable name. In the past this var
    #   got accidentally smashed by deriving tests storing env as well for
    #   legacy reasons.
    @__testcase_env = ENV.to_h

    # Set sepcial env var to check if a code path runs under test. This should
    # be used very very very carefully. The only reason for using this is when
    # a code path needs disabling entirely when under testing.
    ENV['PANGEA_UNDER_TEST'] = 'true'

    Retry.disable_sleeping if defined?(Retry)

    # Make sure we reset $?, so tests can freely mock system and ``
    reset_child_status!
    # FIXME: Drop when VCR gets fixed
    WebMock.enable!

    # Make sure smtp can't be used without mocking it.
    Net::SMTP.stubs(:new).raises(StandardError, 'do not actively use smtp in tests')
    Net::SMTP.stubs(:start).raises(StandardError, 'do not actively use smtp in tests')
  end

  def priority_teardown
    Dir.chdir(@previous_pwd)
    FileUtils.rm_rf(@tmpdir)
    # Restore ENV
    ENV.replace(@__testcase_env) if @__testcase_env
  end

  def _method_name
    return @method_name if defined?(:@method_name)

    index = 0
    caller = ''
    until caller.start_with?('test_')
      caller = caller_locations(index, 1)[0].label
      index += 1
    end
    caller
  end

  def data(path = nil)
    caller = _method_name
    file = File.join(*[@datadir, caller, path].compact)
    return file if File.exist?(file)

    raise "Could not find data path #{file}"
  end

  # Different from data in that it does not assume ext will be a directory
  # but a simple extension. i.e.
  # data/caller.foo instead of data/caller/foo
  def fixture_file(ext)
    caller = _method_name
    file = File.join(*[@datadir, "#{caller}#{ext}"].compact)
    return file if File.exist?(file)

    raise "Could not find data file #{file}"
  end

  # The data dir for the entire test file (not restricted by test method name)
  attr_reader :datadir

  def fake_home(home = Dir.pwd, &block)
    home_ = ENV.fetch('HOME')
    ENV['HOME'] = home
    block.yield
  ensure
    ENV['HOME'] = home_
  end

  def reset_child_status!
    system('true') # Resets $? to all good
  end
end

class AllTestCasesArePangeaCases < TestCase
  # This is a super special hack. We'll want to assert that all TestCases
  # run are in fact derived from this class. But, since we use parallel to
  # quickly run tests in multiple processes at the same time (bypassing the GIL)
  # we cannot simply have a test that asserts it, as that test may be run in
  # set A but not set B and set B may have offending test cases.
  # To deal with this any set that includes any of our TestCase will have
  # this suite forcefully added to assert that everything is alright.
  #
  # For future reference: the class name may need PID mutation to avoid
  # conflicts in the output junit data. Unclear if this is a problem though.
  def test_all_testcases_are_pangea_testcases_test
    not_pangea = []
    ObjectSpace.each_object do |obj|
      next unless obj.is_a?(Class)
      next if obj == Test::Unit::TestCase
      # Hacky workaround. For unknown reasons the mobile CI fails semi-randomly
      # on getting objects which are Class but have an ancestors that is a
      # string. What is most peculiar about this is that the object is entirely
      # uninspectable and everything simply returns an XML string.
      # My theory is that something in the CI reporter stack is an object
      # which somehow managed to override every single method to return to_s,
      # I have no clue how or why, but given the problem is consistently showing
      # the XML string in the output it must be that. While that sucks beyond
      # comprehension, simply guarding against this should make the test work
      # reliably.
      next if obj.ancestors.is_a?(String) || !obj.ancestors.respond_to?(:any?)
      next unless obj.ancestors.any? do |ancestor|
        ancestor == Test::Unit::TestCase
      end

      not_pangea << obj unless obj.ancestors.include?(TestCase)
    end

    assert_empty(not_pangea, 'Found test cases which do not derive from the' \
                             ' pangea specific TestCase class.')
  end
end
