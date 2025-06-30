# ClipboardUtils module provides clipboard functionality
module ClipboardUtils
  # Copies the given text to the macOS clipboard using pbcopy.
  #
  # text - The String to copy.
  #
  # Returns nothing.
  def copy_to_clipboard(text)
    IO.popen("pbcopy", "w") { |f| f << text }
  rescue Errno::ENOENT
    # pbcopy not available (not on macOS), skip clipboard operation
    puts "Warning: Clipboard functionality not available (pbcopy not found)"
  end

  # Check if clipboard functionality is available
  #
  # Returns Boolean indicating if pbcopy is available
  def clipboard_available?
    system("which pbcopy > /dev/null 2>&1")
  end
end