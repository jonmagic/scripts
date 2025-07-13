# lib/github_deep_research_agent/end_node.rb
#
# EndNode: Clean termination point for the research workflow

require_relative "../pocketflow"

module GitHubDeepResearchAgent
  class EndNode < Pocketflow::Node
    def exec(*)
      # This node does nothing - it's just a clean termination point
      nil
    end
  end
end
