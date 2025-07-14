require "logger"

module Log
  def self.logger
    @logger ||= Logger.new($stdout, level: Logger::INFO)
  end

  def self.logger=(logger)
    @logger = logger
  end

  class NullLogger
    def debug(*); end
    def info(*); end
    def warn(*); end
    def error(*); end
    def fatal(*); end
    def unknown(*); end
  end

  NULL = NullLogger.new
end
