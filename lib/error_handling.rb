# ErrorHandling module provides consistent error handling across scripts
module ErrorHandling
  # Exits the script with an error message.
  #
  # message - The String error message to display.
  #
  # Returns nothing. Exits the script with status 1.
  def error_exit(message)
    puts "Error: #{message}"
    exit 1
  end
end
