#!/usr/bin/env ruby

# Simple test script for github-conversations-research-agent
# This tests basic functionality without requiring actual LLM/Qdrant dependencies

require "tempfile"
require "json"

puts "Testing github-conversations-research-agent..."

# Test 1: Help message
puts "\n1. Testing help message..."
result = system("./bin/github-conversations-research-agent --help > /dev/null")
if result
  puts "✓ Help message works"
else
  puts "✗ Help message failed"
  exit 1
end

# Test 2: Missing required arguments
puts "\n2. Testing missing arguments..."
result = system("./bin/github-conversations-research-agent 2>/dev/null")
if !result
  puts "✓ Correctly rejects missing arguments"
else
  puts "✗ Should have failed with missing arguments"
  exit 1
end

# Test 3: Missing collection
puts "\n3. Testing missing collection..."
result = system("./bin/github-conversations-research-agent \"test question\" 2>/dev/null")
if !result
  puts "✓ Correctly rejects missing collection"
else
  puts "✗ Should have failed with missing collection"
  exit 1
end

# Test 4: Basic structure check
puts "\n4. Testing script structure..."
script_content = File.read("bin/github-conversations-research-agent")

required_elements = [
  "InitialResearchNode",
  "AskClarifyingNode", 
  "DeepResearchNode",
  "FinalReportNode",
  "ASK_CLARIFY_PROMPT",
  "DEEP_RESEARCH_PROMPT",
  "FINAL_REPORT_PROMPT",
  "require_relative \"../lib/pocketflow\""
]

required_elements.each do |element|
  if script_content.include?(element)
    puts "✓ Found #{element}"
  else
    puts "✗ Missing #{element}"
    exit 1
  end
end

# Test 5: Check if Pocketflow is vendored correctly
puts "\n5. Testing Pocketflow library..."
if File.exist?("lib/pocketflow.rb")
  pocketflow_content = File.read("lib/pocketflow.rb")
  if pocketflow_content.include?("module Pocketflow")
    puts "✓ Pocketflow library vendored correctly"
  else
    puts "✗ Pocketflow library content invalid"
    exit 1
  end
else
  puts "✗ Pocketflow library not found"
  exit 1
end

# Test 6: Template filling functionality
puts "\n6. Testing template functionality..."

# Since the functions are defined in the script and not easily extracted,
# we'll just check if the script can be loaded without syntax errors
begin
  # Test basic Ruby syntax by checking the script
  result = system("ruby -c bin/github-conversations-research-agent > /dev/null 2>&1")
  if result
    puts "✓ Script syntax is valid"
  else
    puts "✗ Script has syntax errors"
    exit 1
  end
rescue => e
  puts "✗ Error testing script syntax: #{e.message}"
  exit 1
end

puts "\n✓ All basic tests passed!"
puts "\nNote: This script requires actual dependencies (llm CLI, Qdrant) for full functionality testing."
puts "For complete testing, ensure you have:"
puts "- llm CLI installed and configured"
puts "- Qdrant server running with indexed GitHub conversations"
puts "- EDITOR environment variable set"
puts "- A valid collection name"

puts "\nExample full test command:"
puts 'EDITOR=true ./bin/github-conversations-research-agent "test question" --collection github-conversations --max-depth 1 --verbose'