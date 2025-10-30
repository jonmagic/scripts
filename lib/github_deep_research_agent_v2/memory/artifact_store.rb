# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../models/artifact"

module GitHubDeepResearchAgentV2
  module Memory
    # ArtifactStore manages external storage of research artifacts
    class ArtifactStore
      attr_reader :run_id, :base_path

      def initialize(run_id:, base_path: "./cache/deep_research_v2")
        @run_id = run_id
        @base_path = base_path
        @storage_path = File.join(@base_path, run_id)
        @artifacts_file = File.join(@storage_path, "artifacts.jsonl")
        FileUtils.mkdir_p(@storage_path)
      end

      # Store an artifact
      def store(artifact)
        raise ArgumentError, "Invalid artifact" unless artifact.is_a?(Models::Artifact)
        raise ArgumentError, "Artifact validation failed" unless artifact.valid?

        File.open(@artifacts_file, "a") do |f|
          f.puts(JSON.generate(artifact.to_h))
        end
        artifact
      end

      # Load all artifacts
      def load_all
        return [] unless File.exist?(@artifacts_file)
        
        artifacts = []
        File.foreach(@artifacts_file) do |line|
          next if line.strip.empty?
          hash = JSON.parse(line.strip)
          artifacts << Models::Artifact.from_h(hash)
        end
        artifacts
      end

      # Load artifacts by type
      def load_by_type(type)
        load_all.select { |a| a.type == type }
      end

      # Load artifacts by type with data matching criteria
      def query(type:, **criteria)
        load_by_type(type).select do |artifact|
          criteria.all? do |key, value|
            artifact.data[key.to_s] == value || artifact.data[key] == value
          end
        end
      end

      # Count artifacts by type
      def count_by_type(type)
        load_by_type(type).length
      end

      # Get all unique source URLs from facts
      def unique_sources
        facts = load_by_type("fact")
        sources = Set.new
        facts.each do |artifact|
          urls = artifact.data["source_urls"] || []
          sources.merge(urls)
        end
        sources.to_a
      end

      # Clear all artifacts (for testing)
      def clear
        FileUtils.rm_f(@artifacts_file)
      end

      # Get storage stats
      def stats
        artifacts = load_all
        {
          total_artifacts: artifacts.length,
          by_type: artifacts.group_by(&:type).transform_values(&:count),
          storage_path: @storage_path,
          file_size: File.exist?(@artifacts_file) ? File.size(@artifacts_file) : 0
        }
      end
    end
  end
end
