require 'open3'

# ShellUtils module provides common shell command utilities
module ShellUtils
  # Execute a shell command and return stdout, stderr, and exit status
  #
  # cmd - String command to execute
  # stdin_data - Optional String data to send to stdin
  #
  # Returns Hash with :stdout, :stderr, :success keys
  def execute_command(cmd, stdin_data: nil)
    stdout, stderr, status = Open3.capture3(cmd, stdin_data: stdin_data)
    {
      stdout: stdout,
      stderr: stderr,
      success: status.success?,
      exit_code: status.exitstatus
    }
  rescue Errno::ENOENT => e
    # Handle case where command doesn't exist
    {
      stdout: "",
      stderr: e.message,
      success: false,
      exit_code: 127
    }
  end

  # Execute a command and return only stdout, raising on failure
  #
  # cmd - String command to execute
  # stdin_data - Optional String data to send to stdin
  #
  # Returns String stdout
  # Raises RuntimeError if command fails
  def execute_command!(cmd, stdin_data: nil)
    result = execute_command(cmd, stdin_data: stdin_data)
    unless result[:success]
      raise "Command failed (exit #{result[:exit_code]}): #{cmd}\n#{result[:stderr]}"
    end
    result[:stdout]
  end

  # Check if a command exists in PATH
  #
  # cmd - String command name
  #
  # Returns Boolean
  def command_exists?(cmd)
    system("which #{cmd} > /dev/null 2>&1")
  end
end