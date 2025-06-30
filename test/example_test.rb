require_relative 'test_helper'

class ExampleTest < Minitest::Test
  def test_ruby_version
    assert RUBY_VERSION >= "3.0", "Ruby version should be 3.0 or higher"
  end

  def test_minitest_works
    assert_equal 4, 2 + 2
    assert_includes [1, 2, 3], 2
  end

  def test_temp_file_helper
    file = create_temp_file("Hello, World!")
    file.rewind
    assert_equal "Hello, World!", file.read
    file.close
  end

  def test_temp_directory_helper
    setup_temp_directory
    assert File.exist?(@temp_dir)
    assert File.directory?(@temp_dir)
    teardown_temp_directory
    refute File.exist?(@temp_dir)
  end
end