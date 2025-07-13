# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "logger"
require "minitest/autorun"

LOG = Logger.new(IO::NULL) unless defined?(LOG)
