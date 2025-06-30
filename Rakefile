require 'rake/testtask'

# Default task
task default: :test

# Test task - now only runs integration tests
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/integration/*_test.rb']
  t.verbose = true
end

# Integration test task
Rake::TestTask.new(:integration) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/integration/*_test.rb']
  t.verbose = true
end

desc "Show test statistics"
task :stats do
  puts "Test Statistics:"
  puts "================"
  integration_tests = Dir['test/integration/*_test.rb'].length
  puts "Integration tests: #{integration_tests}"
  puts "Total: #{integration_tests}"
end
