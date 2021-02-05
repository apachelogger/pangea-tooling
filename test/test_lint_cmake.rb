require_relative '../lib/lint/log/cmake'
require_relative 'lib/testcase'

# Test lint cmake
class LintCMakeTest < TestCase
  def data
    @path = super
    File.read(@path)
  end

  def test_init
    r = Lint::Log::CMake.new.lint(data)
    assert(!r.valid)
    assert(r.informations.empty?)
    assert(r.warnings.empty?)
    assert(r.errors.empty?)
  end

  def test_missing_package
    r = Lint::Log::CMake.new.lint(data)
    assert(r.valid)
    assert_equal(%w[KF5Package], r.warnings)
  end

  def test_optional
    r = Lint::Log::CMake.new.lint(data)
    assert(r.valid)
    assert_equal(%w[Qt5TextToSpeech], r.warnings)
  end

  def test_warning
    r = Lint::Log::CMake.new.lint(data)
    assert(r.valid)
    assert_equal(%w[], r.warnings)
  end

  def test_disabled_feature
    r = Lint::Log::CMake.new.lint(data)
    assert(r.valid)
    assert_equal(['XCB-CURSOR , Required for XCursor support'], r.warnings)
  end

  def test_missing_runtime
    r = Lint::Log::CMake.new.lint(data)
    assert(r.valid)
    assert_equal(['Qt5Multimedia'], r.warnings)
  end

  def test_ignore_warning_by_release
    data
    ENV['DIST'] = 'xenial'
    r = Lint::Log::CMake.new.tap do |cmake|
      cmake.load_include_ignores("#{@path}-cmake-ignore")
    end.lint(data)
    assert(r.valid)
    assert_equal(['XCB-CURSOR , Required for XCursor support'], r.warnings)
  end

  def test_ignore_warning_by_release_yaml_no_series
    data
    ENV['DIST'] = 'xenial'
    r = Lint::Log::CMake.new.tap do |cmake|
      cmake.load_include_ignores("#{@path}-cmake-ignore")
    end.lint(data)
    assert(r.valid)
    assert_equal([], r.warnings)
  end

  def test_ignore_warning_by_release_basic
    data
    ENV['DIST'] = 'xenial'
    r = Lint::Log::CMake.new.tap do |cmake|
      cmake.load_include_ignores("#{@path}-cmake-ignore")
    end.lint(data)
    assert(r.valid)
    assert_equal(['QCH , API documentation in QCH format (for e.g. Qt Assistant, Qt Creator & KDevelop)'], r.warnings)
  end

  def test_ignore_warning_by_release_basic_multiline
    data
    ENV['DIST'] = 'xenial'
    r = Lint::Log::CMake.new.tap do |cmake|
      cmake.load_include_ignores("#{@path}-cmake-ignore")
    end.lint(data)
    assert(r.valid)
    assert_equal([], r.warnings)
  end

  def test_ignore_warning_by_release_bionic
    data
    ENV['DIST'] = 'bionic'
    r = Lint::Log::CMake.new.tap do |cmake|
      cmake.load_include_ignores("#{@path}-cmake-ignore")
    end.lint(data)
    assert(r.valid)
    assert_equal(['XCB-CURSOR , Required for XCursor support', 'QCH , API documentation in QCH format (for e.g. Qt Assistant, Qt Creator & KDevelop)'], r.warnings)
  end
end
