module GitHubDeepResearchAgent
  # EndNode provides clean workflow termination for the research pipeline.
  #
  # This node serves as the designated termination point for the GitHub research
  # workflow. It accepts any input and returns nil to signal workflow completion
  # to the Pocketflow engine.
  #
  # @note This node intentionally implements only the exec() method since it serves
  #       as a termination point and doesn't require preparation or post-processing.
  class EndNode < Pocketflow::Node
    # Terminates the workflow by returning nil to the Pocketflow engine.
    #
    # @param * [Any] Accepts any parameters from upstream nodes (ignored)
    # @return [nil] Signals workflow termination
    def exec(*)
      # Clean termination point - returns nil to signal workflow completion
      nil
    end
  end
end
