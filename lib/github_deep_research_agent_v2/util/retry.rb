# frozen_string_literal: true

module GitHubDeepResearchAgentV2
  module Util
    # Retry provides retry logic with exponential backoff
    module Retry
      DEFAULT_MAX_ATTEMPTS = 3
      DEFAULT_BASE_DELAY = 1
      DEFAULT_MAX_DELAY = 10

      # Execute block with retry logic
      #
      # @param max_attempts [Integer] Maximum number of attempts
      # @param base_delay [Float] Base delay in seconds for exponential backoff
      # @param max_delay [Float] Maximum delay in seconds
      # @param logger [Logger] Optional logger for retry messages
      # @yield Block to execute with retry
      # @return Result of block execution
      def self.with_retry(max_attempts: DEFAULT_MAX_ATTEMPTS, base_delay: DEFAULT_BASE_DELAY, 
                          max_delay: DEFAULT_MAX_DELAY, logger: nil)
        attempt = 1
        begin
          yield
        rescue => e
          if attempt < max_attempts
            delay = [base_delay * (2 ** (attempt - 1)), max_delay].min
            logger&.warn("Attempt #{attempt}/#{max_attempts} failed: #{e.message}. Retrying in #{delay}s...")
            sleep(delay)
            attempt += 1
            retry
          else
            logger&.error("All #{max_attempts} attempts failed: #{e.message}")
            raise
          end
        end
      end
    end
  end
end
