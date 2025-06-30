require 'rake/testtask'

# Default task
task default: :test

# Test task
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

# Integration test task
Rake::TestTask.new(:integration) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/integration/*_test.rb']
  t.verbose = true
end

# Unit test task
Rake::TestTask.new(:unit) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/unit/*_test.rb']
  t.verbose = true
end

desc "Run all tests"
task :all => [:unit, :integration]

desc "Show test statistics"
task :stats do
  puts "Test Statistics:"
  puts "================"
  unit_tests = Dir['test/unit/*_test.rb'].length
  integration_tests = Dir['test/integration/*_test.rb'].length
  puts "Unit tests: #{unit_tests}"
  puts "Integration tests: #{integration_tests}"
  puts "Total: #{unit_tests + integration_tests}"
end