module ReflectionAgent
  # EndNode - Completes the reflection workflow
  #
  # This node:
  # 1. Displays completion summary
  # 2. Lists all generated files
  # 3. Provides next steps for the user
  #
  # @example
  #   node = EndNode.new
  #   summary = node.prep(shared)
  #   result = node.exec(summary)
  #   node.post(shared, summary, result)
  class EndNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Gather completion summary
    #
    # @param shared [Hash] Workflow context
    # @return [Hash] Summary data
    def prep(shared)
      @shared = shared
      logger.info "=== STAGE 7: COMPLETION ==="

      reflection_dir = shared[:reflection_dir]

      # Count generated files
      files = {
        metadata: File.join(reflection_dir, "00-session-metadata.json"),
        snippets: File.join(reflection_dir, "01-snippets.json"),
        clusters: File.join(reflection_dir, "02-clusters.json"),
        snippet_summaries: File.join(reflection_dir, "03-cluster-snippet-summaries.json"),
        conversations_all: File.join(reflection_dir, "04-conversations-all.json"),
        conversations_by_cluster: File.join(reflection_dir, "04-conversations-by-cluster.json"),
        conversation_summaries: File.join(reflection_dir, "05-cluster-conversation-summaries.json"),
        final_reflection: File.join(reflection_dir, "final-reflection.md")
      }

      # Count cluster files
      cluster_dir = File.join(reflection_dir, "clusters")
      cluster_files = Dir.glob(File.join(cluster_dir, "*")).sort if File.directory?(cluster_dir)

      # Load metadata for stats
      metadata_path = files[:metadata]
      metadata = JSON.parse(File.read(metadata_path)) if File.exist?(metadata_path)

      {
        reflection_dir: reflection_dir,
        files: files,
        cluster_files: cluster_files || [],
        metadata: metadata
      }
    end

    # Display completion summary
    #
    # @param summary [Hash] Summary data from prep
    # @return [Hash] Completion status
    def exec(summary)
      logger.info ""
      logger.info "=" * 70
      logger.info "  REFLECTION COMPLETE"
      logger.info "=" * 70
      logger.info ""
      logger.info "Period: #{summary[:metadata]["start_date"]} to #{summary[:metadata]["end_date"]}"
      logger.info "Purpose: #{summary[:metadata]["purpose"]}"
      logger.info ""
      logger.info "Output Directory:"
      logger.info "  #{summary[:reflection_dir]}"
      logger.info ""
      logger.info "Generated Files:"
      summary[:files].each do |name, path|
        if File.exist?(path)
          size = File.size(path)
          logger.info "  ✓ #{File.basename(path)} (#{format_bytes(size)})"
        end
      end
      logger.info ""
      logger.info "Cluster Files (#{summary[:cluster_files].length} total):"
      summary[:cluster_files].take(10).each do |path|
        logger.info "  ✓ #{File.basename(path)}"
      end
      if summary[:cluster_files].length > 10
        logger.info "  ... and #{summary[:cluster_files].length - 10} more"
      end
      logger.info ""
      logger.info "=" * 70
      logger.info ""
      logger.info "Next Steps:"
      logger.info "  1. Review the final reflection: #{summary[:files][:final_reflection]}"
      logger.info "  2. Check individual cluster summaries in: #{File.join(summary[:reflection_dir], 'clusters')}"
      logger.info "  3. Edit or annotate the reflection as needed"
      logger.info "  4. Consider adding it to your permanent notes"
      logger.info ""

      { status: "completed", timestamp: Time.now.utc.iso8601 }
    end

    # Write final ledger
    #
    # @param shared [Hash] Workflow context
    # @param prep_res [Hash] Summary from prep
    # @param exec_res [Hash] Result from exec
    # @return [nil]
    def post(shared, prep_res, exec_res)
      # Write final ledger
      ledger = {
        stage: "end",
        status: "completed",
        workflow: "reflection_agent_v2",
        reflection_dir: prep_res[:reflection_dir],
        createdAt: exec_res[:timestamp]
      }
      ledger_path = File.join(shared[:reflection_dir], "stage-7-end.ledger.json")
      File.write(ledger_path, JSON.pretty_generate(ledger))

      nil
    end

    private

    # Format bytes into human-readable string
    #
    # @param bytes [Integer] File size in bytes
    # @return [String] Formatted size
    def format_bytes(bytes)
      if bytes < 1024
        "#{bytes}B"
      elsif bytes < 1024 * 1024
        "#{(bytes / 1024.0).round(1)}KB"
      else
        "#{(bytes / (1024.0 * 1024)).round(1)}MB"
      end
    end
  end
end
