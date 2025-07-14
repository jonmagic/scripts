# GitHubDeepResearchAgent - Multi-Stage Research Pipeline for GitHub Conversations
#
# ## Architecture Overview
# This module orchestrates a multi-node workflow for deep research on GitHub issues, PRs, and
# discussions. It combines keyword and semantic search, LLM-powered summarization, topic extraction,
# and interactive research loops.
#
# ### Pipeline & Node Roles
# - **PlannerNode**: The central coordinator and "brain" of the workflow. It decomposes the research
#   question into actionable search plans, manages iteration depth, research memory, and routes
#   control to other nodes. All major decisions and workflow branching originate here.
# - **RetrieverNode**: Acts as the "search engine" of the pipeline. It executes search plans
#   (semantic, keyword, or hybrid), fetches and enriches GitHub conversations, and updates research
#   memory for downstream analysis. RetrieverNode is always invoked by PlannerNode and returns
#   results for further planning or reporting.
# - **InitialResearchNode**: Handles initial query parsing and bootstraps the research context.
# - **AskClarifyingNode**: Generates clarifying questions to improve research focus, as directed by
#   PlannerNode.
# - **ContextCompactionNode**: Compacts and prunes context to fit LLM or memory constraints,
#   typically after several research iterations.
#   research is complete.
# - **ClaimVerifierNode**: Verifies claims or hypotheses using retrieved evidence, under
#   PlannerNode's direction.
# - **FinalReportNode**: Synthesizes findings into a final report when PlannerNode determines
# - **EndNode**: Terminates the workflow and returns results.
#
# ### Data Flow
# 1. **PlannerNode** receives the initial research question and generates a search plan.
# 2. **RetrieverNode** executes the plan, retrieving and enriching relevant conversations.
# 3. Results are routed back to **PlannerNode**, which may trigger further planning, clarification,
#    verification, or compaction as needed.
# 4. The workflow continues, with PlannerNode as the central decision-maker, until it determines
#    sufficient information has been gathered, at which point **FinalReportNode** is invoked.
#
# ### Integration Patterns
# - **LLM Integration**: All LLM calls are made via the `llm` CLI (never direct library imports)
# - **Vector Search**: Uses Qdrant for semantic search with flat JSON metadata
# - **GitHub API**: Fetches data via `gh` CLI GraphQL queries
# - **Caching**: Hierarchical cache in `data/` for raw, summary, and topic data
#
# ### Error Handling
# - Each node implements `prep`, `exec`, and `post` with automatic error handling and retry logic
# - Failures in one node do not halt the entire workflow; errors are logged and degraded gracefully
#
# ### Extensibility
# - Add new nodes by subclassing `Pocketflow::Node` and updating the workflow chain
# - All nodes are loosely coupled and communicate via the shared context
#
# For detailed node documentation, see each class in `lib/github_deep_research_agent/`.

require "json"
require "open3"
require "set"
require "shellwords"
require "tempfile"

require_relative "log"
require_relative "pocketflow"
require_relative "utils"

require_relative "github_deep_research_agent/ask_clarifying_node"
require_relative "github_deep_research_agent/context_compaction_node"
require_relative "github_deep_research_agent/claim_verifier_node"
require_relative "github_deep_research_agent/end_node"
require_relative "github_deep_research_agent/final_report_node"
require_relative "github_deep_research_agent/initial_research_node"
require_relative "github_deep_research_agent/planner_node"
require_relative "github_deep_research_agent/retriever_node"

module GitHubDeepResearchAgent
end
