require_relative 'error_handling'

# DependencyChecker module provides dependency checking functionality
module DependencyChecker
  include ErrorHandling

  # Checks if a required command-line dependency is available in PATH.
  #
  # cmd - The String name of the command to check.
  #
  # Returns nothing. Exits if not found.
  def check_dependency(cmd)
    system("which #{cmd} > /dev/null 2>&1") || error_exit("Required dependency '#{cmd}' not found in PATH.")
  end

  # Checks multiple dependencies at once.
  #
  # cmds - Array of String command names to check.
  #
  # Returns nothing. Exits if any not found.
  def check_dependencies(*cmds)
    cmds.each { |cmd| check_dependency(cmd) }
  end
end
