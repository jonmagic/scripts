module ReflectionAgent
  # SnippetsLoaderNode - Loads all weekly snippets within date range
  #
  # This node scans the Snippets folder and loads all snippet files that
  # overlap with the reflection period. Snippets are the PRIMARY signal
  # for the reflection - they represent what you already deemed important.
  #
  # Supports two formats:
  # - Single files: YYYY-MM-DD-to-YYYY-MM-DD.md
  # - Folders: YYYY-MM-DD-to-YYYY-MM-DD/snippets.md (or final_snippet.md, etc.)
  #
  # @example
  #   node = SnippetsLoaderNode.new
  #   snippets_path = node.prep(shared)
  #   snippets = node.exec(snippets_path)
  #   node.post(shared, snippets_path, snippets)
  class SnippetsLoaderNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Get snippets directory path
    #
    # @param shared [Hash] Workflow context
    # @return [String] Path to Snippets folder
    def prep(shared)
      @shared = shared
      logger.info "=== STAGE 1: LOAD SNIPPETS ==="

      File.join(shared[:brain_path], "Snippets")
    end

    # Scan and load all relevant snippets
    #
    # @param snippets_path [String] Path from prep
    # @return [Array<Hash>] Loaded snippets
    def exec(snippets_path)
      start_date = Date.parse(@shared[:start_date])
      end_date = Date.parse(@shared[:end_date])
      snippets = []

      unless File.directory?(snippets_path)
        logger.warn "Snippets directory not found: #{snippets_path}"
        return snippets
      end

      # Pattern 1: Single markdown files (YYYY-MM-DD-to-YYYY-MM-DD.md)
      Dir.glob(File.join(snippets_path, "*.md")).each do |file|
        filename = File.basename(file, ".md")
        dates = extract_date_range_from_name(filename)

        if dates && dates[:start] <= end_date && dates[:end] >= start_date
          snippets << {
            path: file,
            start_date: dates[:start].to_s,
            end_date: dates[:end].to_s,
            title: filename,
            content: File.read(file),
            source: "file"
          }
          logger.info "  ✨ Loaded snippet: #{filename}"
        end
      end

      # Pattern 2: Folders with snippet files inside
      Dir.glob(File.join(snippets_path, "*")).each do |folder|
        next unless File.directory?(folder)

        folder_name = File.basename(folder)
        dates = extract_date_range_from_name(folder_name)

        next unless dates && dates[:start] <= end_date && dates[:end] >= start_date

                # Priority order for snippet files in folders
        snippet_files = [
          "final_snippet.md",
          "snippets.md",
          "09_snippets.md",
          "08_snippets.md",
          "07_snippets.md",
          "output.md",
          "draft.md"
        ]

        found = false
        snippet_files.each do |snippet_file|
          file_path = File.join(folder, snippet_file)
          if File.exist?(file_path)
            snippets << {
              path: file_path,
              start_date: dates[:start].to_s,
              end_date: dates[:end].to_s,
              title: "#{folder_name}/#{snippet_file}",
              content: File.read(file_path),
              source: "folder"
            }
            logger.info "  ✨ Loaded snippet: #{folder_name}/#{snippet_file}"
            found = true
            break # Only take the first matching file
          end
        end

        # Fallback: find any .md file in the directory
        unless found
          md_files = Dir.glob(File.join(folder, "*.md")).sort.reverse
          if md_files.any?
            file_path = md_files.first
            snippets << {
              path: file_path,
              start_date: dates[:start].to_s,
              end_date: dates[:end].to_s,
              title: "#{folder_name}/#{File.basename(file_path)}",
              content: File.read(file_path),
              source: "folder"
            }
            logger.info "  ✨ Loaded snippet: #{folder_name}/#{File.basename(file_path)}"
          end
        end
      end

      # Sort by start date
      snippets.sort_by! { |s| s[:start_date] }

      logger.info ""
      logger.info "Loaded #{snippets.length} snippets total"
      logger.info ""

      snippets
    end

    # Write snippets to disk and update shared context
    #
    # @param shared [Hash] Workflow context
    # @param prep_res [String] Snippets path from prep
    # @param exec_res [Array<Hash>] Loaded snippets
    # @return [nil]
    def post(shared, prep_res, exec_res)
      # Write snippets data
      snippets_path = File.join(shared[:reflection_dir], "01-snippets.json")
      File.write(snippets_path, JSON.pretty_generate(exec_res))
      logger.info "Wrote snippets: #{snippets_path}"

      # Write ledger
      ledger = {
        stage: "snippets_loader",
        status: "completed",
        snippets_count: exec_res.length,
        next: "snippets_cluster",
        createdAt: Time.now.utc.iso8601
      }
      ledger_path = File.join(shared[:reflection_dir], "stage-1-snippets-loader.ledger.json")
      File.write(ledger_path, JSON.pretty_generate(ledger))

      logger.info ""
      logger.info "✓ Stage 1 complete: Loaded #{exec_res.length} snippets"
      logger.info "  Next: Cluster snippets by theme"
      logger.info ""

      nil
    end

    private

    # Extract date range from snippet folder/file name
    #
    # @param name [String] Folder or filename
    # @return [Hash, nil] Hash with :start and :end dates, or nil
    def extract_date_range_from_name(name)
      # Pattern: YYYY-MM-DD-to-YYYY-MM-DD (with optional leading zeros)
      if match = name.match(/(\d{4}-\d{1,2}-\d{1,2})-to-(\d{4}-\d{1,2}-\d{1,2})/)
        begin
          # Normalize dates (add leading zeros if needed)
          start_str = match[1].split('-').map { |p| p.rjust(p.length < 3 ? 2 : 4, '0') }.join('-')
          end_str = match[2].split('-').map { |p| p.rjust(p.length < 3 ? 2 : 4, '0') }.join('-')

          {
            start: Date.parse(start_str),
            end: Date.parse(end_str)
          }
        rescue Date::Error
          nil
        end
      end
    end
  end
end
