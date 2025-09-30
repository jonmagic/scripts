module ReflectionAgent
  # SnippetsClusterNode - Groups snippets into temporal clusters
  #
  # This node creates 4-6 clusters of snippets based on time periods.
  # For shorter reflections (≤4 weeks), uses weekly clusters.
  # For longer reflections, groups into monthly or multi-week chunks.
  #
  # Goal: Each cluster should have 3-8 snippets for optimal LLM processing.
  #
  # @example
  #   node = SnippetsClusterNode.new
  #   snippets = node.prep(shared)
  #   clusters = node.exec(snippets)
  #   node.post(shared, snippets, clusters)
  class SnippetsClusterNode < Pocketflow::Node
    attr_accessor :logger

    def initialize(*args, logger: Log.logger, **kwargs)
      super(*args, **kwargs)
      @logger = logger
    end

    # Load snippets from previous stage
    #
    # @param shared [Hash] Workflow context
    # @return [Array<Hash>] Loaded snippets
    def prep(shared)
      @shared = shared
      logger.info "=== STAGE 2: CLUSTER SNIPPETS ==="

      snippets_path = File.join(shared[:reflection_dir], "01-snippets.json")
      JSON.parse(File.read(snippets_path))
    end

    # Create temporal clusters of snippets
    #
    # @param snippets [Array<Hash>] Snippets from prep
    # @return [Array<Hash>] Clusters with assigned snippets
    def exec(snippets)
      return [] if snippets.empty?

      start_date = Date.parse(@shared[:start_date])
      end_date = Date.parse(@shared[:end_date])
      total_days = (end_date - start_date).to_i + 1

      logger.info "Date range: #{total_days} days (#{start_date} to #{end_date})"
      logger.info "Total snippets: #{snippets.length}"

      # Determine clustering strategy based on time span
      clusters = if total_days <= 28
        # ≤4 weeks: Weekly clusters
        cluster_by_weeks(snippets, start_date, end_date)
      elsif total_days <= 90
        # ≤3 months: Bi-weekly clusters
        cluster_by_period(snippets, start_date, end_date, 14)
      elsif total_days <= 180
        # ≤6 months: Monthly clusters
        cluster_by_months(snippets, start_date, end_date)
      else
        # >6 months: 6-week clusters
        cluster_by_period(snippets, start_date, end_date, 42)
      end

      logger.info ""
      logger.info "Created #{clusters.length} clusters:"
      clusters.each do |cluster|
        logger.info "  #{cluster[:name]}: #{cluster[:snippets].length} snippets"
      end
      logger.info ""

      clusters
    end

    # Write clusters to disk
    #
    # @param shared [Hash] Workflow context
    # @param prep_res [Array<Hash>] Snippets from prep
    # @param exec_res [Array<Hash>] Clusters
    # @return [nil]
    def post(shared, prep_res, exec_res)
      # Write clusters metadata
      clusters_path = File.join(shared[:reflection_dir], "02-clusters.json")
      File.write(clusters_path, JSON.pretty_generate(exec_res))
      logger.info "Wrote clusters: #{clusters_path}"

      # Write ledger
      ledger = {
        stage: "snippets_cluster",
        status: "completed",
        clusters_count: exec_res.length,
        next: "cluster_snippet_summary",
        createdAt: Time.now.utc.iso8601
      }
      ledger_path = File.join(shared[:reflection_dir], "stage-2-snippets-cluster.ledger.json")
      File.write(ledger_path, JSON.pretty_generate(ledger))

      logger.info ""
      logger.info "✓ Stage 2 complete: Created #{exec_res.length} clusters"
      logger.info "  Next: Summarize each cluster's snippets"
      logger.info ""

      nil
    end

    private

    # Cluster snippets by week
    #
    # @param snippets [Array<Hash>] All snippets
    # @param start_date [Date] Period start
    # @param end_date [Date] Period end
    # @return [Array<Hash>] Weekly clusters
    def cluster_by_weeks(snippets, start_date, end_date)
      clusters = []
      current = start_date

      while current <= end_date
        week_end = [current + 6, end_date].min
        week_snippets = snippets.select do |s|
          snippet_start = Date.parse(s["start_date"])
          snippet_end = Date.parse(s["end_date"])
          # Snippet overlaps with this week
          snippet_start <= week_end && snippet_end >= current
        end

        if week_snippets.any?
          clusters << {
            id: "week-#{current.strftime('%Y-%m-%d')}",
            name: "Week of #{current.strftime('%b %d, %Y')}",
            start_date: current.to_s,
            end_date: week_end.to_s,
            snippets: week_snippets
          }
        end

        current += 7
      end

      clusters
    end

    # Cluster snippets by month
    #
    # @param snippets [Array<Hash>] All snippets
    # @param start_date [Date] Period start
    # @param end_date [Date] Period end
    # @return [Array<Hash>] Monthly clusters
    def cluster_by_months(snippets, start_date, end_date)
      clusters = []
      current = Date.new(start_date.year, start_date.month, 1)

      while current <= end_date
        month_end = Date.new(current.year, current.month, -1)
        month_end = [month_end, end_date].min

        month_snippets = snippets.select do |s|
          snippet_start = Date.parse(s["start_date"])
          snippet_end = Date.parse(s["end_date"])
          snippet_start <= month_end && snippet_end >= current
        end

        if month_snippets.any?
          clusters << {
            id: "month-#{current.strftime('%Y-%m')}",
            name: current.strftime('%B %Y'),
            start_date: [current, start_date].max.to_s,
            end_date: month_end.to_s,
            snippets: month_snippets
          }
        end

        # Move to next month
        current = current.next_month
      end

      clusters
    end

    # Cluster snippets by fixed period (days)
    #
    # @param snippets [Array<Hash>] All snippets
    # @param start_date [Date] Period start
    # @param end_date [Date] Period end
    # @param period_days [Integer] Days per cluster
    # @return [Array<Hash>] Period clusters
    def cluster_by_period(snippets, start_date, end_date, period_days)
      clusters = []
      current = start_date
      cluster_num = 1

      while current <= end_date
        period_end = [current + period_days - 1, end_date].min

        period_snippets = snippets.select do |s|
          snippet_start = Date.parse(s["start_date"])
          snippet_end = Date.parse(s["end_date"])
          snippet_start <= period_end && snippet_end >= current
        end

        if period_snippets.any?
          clusters << {
            id: "period-#{cluster_num}",
            name: "#{current.strftime('%b %d')} - #{period_end.strftime('%b %d, %Y')}",
            start_date: current.to_s,
            end_date: period_end.to_s,
            snippets: period_snippets
          }
          cluster_num += 1
        end

        current += period_days
      end

      clusters
    end
  end
end
