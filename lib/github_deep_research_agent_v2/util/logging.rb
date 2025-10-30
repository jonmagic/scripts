# frozen_string_literal: true

require "logger"

module GitHubDeepResearchAgentV2
  module Util
    # Logging provides standardized logging utilities
    module Logging
      # Create a logger with appropriate formatting
      def self.create_logger(level: Logger::INFO, output: $stdout)
        logger = Logger.new(output)
        logger.level = level
        logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
        end
        logger
      end

      # Parse log level from string
      def self.parse_level(level_str)
        case level_str&.downcase
        when "debug" then Logger::DEBUG
        when "info" then Logger::INFO
        when "warn" then Logger::WARN
        when "error" then Logger::ERROR
        when "fatal" then Logger::FATAL
        else Logger::INFO
        end
      end
    end
  end
end
