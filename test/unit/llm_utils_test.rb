require_relative '../test_helper'
require 'llm_utils'

class LlmUtilsTest < Minitest::Test
  include LlmUtils

  def test_llm_model_flag_with_model
    result = llm_model_flag("gpt-4.1")
    assert_equal "-m gpt-4.1", result
  end

  def test_llm_model_flag_with_nil
    result = llm_model_flag(nil)
    assert_equal "", result
  end

  def test_llm_model_flag_with_empty_string
    result = llm_model_flag("")
    assert_equal "", result
  end

  def test_llm_model_flag_with_whitespace_only
    result = llm_model_flag("   ")
    assert_equal "", result
  end

  def test_llm_model_flag_with_special_characters
    result = llm_model_flag("model-with-dashes")
    assert_equal "-m model-with-dashes", result
  end

  def test_llm_model_flag_escapes_shell_characters
    result = llm_model_flag("model with spaces")
    assert_includes result, "model\\ with\\ spaces"
  end

  def test_execute_llm_method_exists
    assert_respond_to self, :execute_llm
  end
end
