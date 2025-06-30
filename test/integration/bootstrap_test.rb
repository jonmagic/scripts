require_relative '../test_helper'

class BootstrapIntegrationTest < Minitest::Test
  def setup
    @script_path = File.expand_path('../../../bin/bootstrap', __FILE__)
  end

  def test_bootstrap_script_exists
    assert File.exist?(@script_path), "Bootstrap script should exist"
    assert File.executable?(@script_path), "Bootstrap script should be executable"
  end

  def test_bootstrap_script_has_shebang
    first_line = File.read(@script_path).lines.first
    assert_match /^#!/, first_line
  end

  def test_bootstrap_script_checks_for_homebrew
    content = File.read(@script_path)
    assert_includes content, "brew", "Bootstrap script should mention brew"
    assert_includes content, "Homebrew", "Bootstrap script should check for Homebrew"
  end

  def test_bootstrap_script_checks_for_dependencies
    content = File.read(@script_path)
    %w[fzf llm gh].each do |dep|
      assert_includes content, dep, "Bootstrap script should check for #{dep}"
    end
  end
end
