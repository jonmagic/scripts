module ReflectionAgent
  # InitializeNode - Sets up reflection session and directory structure
  #
  # Creates the reflection directory structure and writes session metadata.
  # Handles date defaults and resume scenarios.
  #
  # @example
  #   node = InitializeNode.new
  #   metadata = node.prep(shared)
  #   result = node.exec(metadata)
  #   node.post(shared, metadata, result)
  class InitializeNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Prepare initialization by gathering inputs and setting defaults
    #
    # @param shared [Hash] Workflow context
    # @return [Hash] Metadata configuration
    def prep(shared)
      logger.info "=== STAGE 0: INITIALIZE ==="

      # Check if resuming from existing reflection
      if shared[:resume_from] && File.directory?(shared[:resume_from])
        logger.info "Resuming from existing reflection: #{shared[:resume_from]}"
        metadata_path = File.join(shared[:resume_from], "00-session-metadata.json")

        if File.exist?(metadata_path)
          metadata = JSON.parse(File.read(metadata_path))
          shared[:reflection_dir] = shared[:resume_from]
          return metadata
        else
          logger.warn "Metadata file not found in resume directory, starting fresh"
        end
      end

      # Calculate date defaults
      end_date = shared[:end_date] || Date.today.to_s
      start_date = shared[:start_date] || (Date.today - 14).to_s

      # Apply defaults
      purpose = shared[:purpose] || "catch-up"
      reflection_name = shared[:reflection_name] || "catch-up-#{end_date}"

      logger.info "Date range: #{start_date} to #{end_date}"
      logger.info "Purpose: #{purpose}"
      logger.info "Name: #{reflection_name}"

      # Build metadata structure
      {
        startDate: start_date,
        endDate: end_date,
        purpose: purpose,
        reflectionName: reflection_name,
        sessionCount: 1,
        currentStage: "initialize",
        stages: {
          initialize: "in-progress",
          snippets_loader: "not-started",
          snippets_cluster: "not-started",
          cluster_snippet_summary: "not-started",
          conversations_loader: "not-started",
          cluster_conversation_summary: "not-started",
          final_synthesis: "not-started"
        },
        createdAt: Time.now.utc.iso8601,
        lastUpdated: Time.now.utc.iso8601,
        brain_path: shared[:brain_path]
      }
    end

    # Create directory structure and write metadata
    #
    # @param metadata [Hash] Metadata from prep
    # @return [Hash] Result with paths
    def exec(metadata)
      # Build reflection directory path
      dir_name = "#{metadata[:startDate]}__to__#{metadata[:endDate]}__#{metadata[:reflectionName]}"
      reflection_dir = File.join(
        metadata[:brain_path],
        "Reflections",
        dir_name
      )

      # Create directory structure
      FileUtils.mkdir_p(reflection_dir)
      FileUtils.mkdir_p(File.join(reflection_dir, "clusters"))

      logger.info "Created reflection directory: #{reflection_dir}"

      # Update metadata
      metadata[:stages][:initialize] = "completed"
      metadata[:currentStage] = "snippets_loader"
      metadata[:lastUpdated] = Time.now.utc.iso8601

      # Write metadata file
      metadata_path = File.join(reflection_dir, "00-session-metadata.json")
      File.write(metadata_path, JSON.pretty_generate(metadata))
      logger.info "Wrote metadata: #{metadata_path}"

      # Write stage ledger
      ledger = {
        stage: "initialize",
        status: "completed",
        next: "snippets_loader",
        createdAt: Time.now.utc.iso8601
      }
      ledger_path = File.join(reflection_dir, "stage-0-init.ledger.json")
      File.write(ledger_path, JSON.pretty_generate(ledger))

      {
        reflection_dir: reflection_dir,
        metadata_path: metadata_path,
        ledger_path: ledger_path
      }
    end

    # Store reflection directory in shared context
    #
    # @param shared [Hash] Workflow context to update
    # @param prep_res [Hash] Metadata from prep
    # @param exec_res [Hash] Result from exec
    # @return [nil]
    def post(shared, prep_res, exec_res)
      shared[:reflection_dir] = exec_res[:reflection_dir]
      shared[:start_date] = prep_res[:startDate]
      shared[:end_date] = prep_res[:endDate]

      logger.info ""
      logger.info "✓ Initialized: #{prep_res[:startDate]} → #{prep_res[:endDate]}"
      logger.info "  #{exec_res[:reflection_dir]}"
      logger.info ""

      nil
    end
  end
end
