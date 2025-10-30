# GitHub Deep Research Agent V2

A next-generation deep research agent for GitHub conversations (issues, PRs, discussions) that provides comprehensive, well-cited research reports with advanced planning, execution, and quality control.

## Overview

The V2 agent implements a sophisticated multi-stage research pipeline:

1. **Dynamic Planning** - Generates structured, multi-aspect research plans
2. **Parallel Execution** - Executes searches concurrently with budget awareness
3. **External Memory** - Manages artifacts in persistent storage with relevance ranking
4. **Policy-Driven Decisions** - Uses configurable policies for continuation/termination
5. **Source Citation** - Ensures all claims are traceable to specific sources

## Key Features

- **Multi-Aspect Planning**: Decomposes complex questions into distinct investigation aspects
- **Plan Verification**: Deterministic validation ensures plan quality before execution
- **Budget Management**: Token tracking prevents runaway costs
- **Relevance Ranking**: Prioritizes most relevant facts for final report
- **Fact Extraction**: Converts raw conversations into atomic, verifiable facts
- **Policy Engine**: Configurable rules for replanning, continuation, or early termination
- **Comprehensive Reports**: Structured Markdown with executive summary, detailed analysis, and full source citations

## Architecture

### Components

#### Core Models
- **Plan**: Structured research plan with aspects, queries, and success criteria
- **Fact**: Atomic piece of information with source URLs and confidence score
- **Summary**: Distilled conversation summary with extracted facts
- **Artifact**: External storage unit for all research data
- **Evaluation**: Mid-run progress assessment

#### Agents
- **Planner**: Generates multi-aspect research plans with LLM
- **PlanVerifier**: Validates plans with deterministic rules
- **ResearchSubAgent**: Executes search and summarization for queries
- **SummarizerAgent**: Extracts facts from conversation text
- **EvaluatorAgent**: Assesses coverage and confidence mid-run
- **ReporterAgent**: Synthesizes final Markdown report with citations
- **PolicyEngine**: Makes continuation/termination decisions

#### Memory & Budget
- **ArtifactStore**: Manages external artifact storage (JSONL format)
- **RelevanceRanker**: Scores and ranks facts by relevance
- **Compaction**: Reduces context size through hierarchical summarization
- **TokenTracker**: Tracks usage across all stages with budget enforcement

#### Search
- **SemanticSearchAdapter**: Wraps semantic search via Qdrant
- **KeywordSearchAdapter**: Wraps GitHub keyword search

### Workflow

```
Question → Planner → Plan → Verifier → [Valid?]
                                           ↓
                               Research Round (per depth)
                                           ↓
                        Execute Searches → Fetch → Summarize → Extract Facts
                                           ↓
                                    Store Artifacts
                                           ↓
                                 Evaluate Progress
                                           ↓
                            Policy Decision [Continue/Replan/Finalize]
                                           ↓
                          Reporter → Final Markdown Report
```

## Installation

The V2 agent requires:

- Ruby 3.2+
- `llm` CLI tool for LLM interactions
- `gh` CLI for GitHub API access
- Running Qdrant instance (for semantic search)
- Existing search scripts from this repository

Ensure dependencies are installed:

```bash
cd /path/to/scripts
bin/bootstrap  # Installs required tools
```

## Usage

### Basic Usage

```bash
bin/github-deep-research-agent-v2 \
  "What caused the performance regression in version 2.0?" \
  --collection github-conversations
```

### Advanced Usage

```bash
bin/github-deep-research-agent-v2 \
  "Analyze the root cause of issue #456" \
  --collection github-conversations \
  --max-depth 3 \
  --breadth 5 \
  --token-budget 60000 \
  --stop-if-confidence 0.85 \
  --min-coverage 0.75 \
  --fast-model gpt-4o-mini \
  --reasoning-model gpt-4o \
  --cache-path ./data \
  --output-path ./reports/issue-456-analysis.md \
  --log-level debug
```

### Configuration Options

#### Required
- `--collection NAME` - Qdrant collection name

#### Search & Execution
- `--max-depth N` - Maximum research iterations (default: 3)
- `--breadth N` - Maximum aspects to investigate (default: 5)
- `--token-budget N` - Total token budget (default: 60000)
- `--parallel-agents N` - Concurrent research agents (default: 4)
- `--max-summaries-per-branch N` - Results per query (default: 6)
- `--search-modes MODE1,MODE2` - Search modes: semantic,keyword (default: both)

#### Policy & Thresholds
- `--stop-if-confidence SCORE` - Early stop threshold (default: 0.85)
- `--min-coverage SCORE` - Minimum coverage required (default: 0.75)
- `--replan-max N` - Maximum replans allowed (default: 2)
- `--relevance-top-k N` - Top facts for report (default: 40)

#### Models
- `--fast-model MODEL` - Fast LLM for light reasoning
- `--reasoning-model MODEL` - LLM for complex analysis
- `--summary-model MODEL` - LLM for summarization

#### Output
- `--report-style STYLE` - detailed or concise (default: detailed)
- `--cache-path PATH` - Cache directory (default: ./cache/deep_research_v2)
- `--output-path PATH` - Report output file
- `--json-artifacts-path PATH` - Artifacts directory

#### Logging
- `--log-level LEVEL` - debug, info, warn, error (default: info)

## Output

### Final Report Structure

```markdown
# Executive Summary
High-level overview of findings

## Key Findings
- Finding 1 [3 sources]
- Finding 2 [5 sources]

## Detailed Analysis
### Aspect: Root Cause
Detailed paragraphs with citations (S1, S3)

### Aspect: Mitigations
...

## Remaining Gaps
- Information still missing
- Areas needing investigation

## Methodology
- Depth reached: 3
- Breadth: 5 aspects
- Token usage: planning=1200, research=35000, ...
- Budget status: within

## Sources
S1: https://github.com/owner/repo/issues/123 – Description
S2: https://github.com/owner/repo/pull/456 – Description
```

### Artifacts

All research artifacts are stored in JSONL format:

```
cache/deep_research_v2/<run_id>/
  artifacts.jsonl        # All artifacts (plans, facts, summaries, evaluations)
  final_report.md        # Final Markdown report
  manifest.json          # Run metadata and statistics
```

### Manifest

```json
{
  "question": "Research question",
  "run_id": "20231215_120000_abc123",
  "plan_version": 2,
  "token_usage": {
    "planning": 1200,
    "research": 35000,
    "summarization": 8000,
    "evaluation": 1500,
    "report": 3000
  },
  "depth_reached": 3,
  "aspects_completed": 5,
  "sources": [
    {"url": "...", "facts_used": 4}
  ],
  "timestamp": "2023-12-15T12:00:00Z"
}
```

## Design Principles

1. **Simplicity over Abstraction** - Clear, focused components without over-engineering
2. **External Memory** - Persistent artifact storage prevents context bloat
3. **Budget Awareness** - Token tracking ensures cost control
4. **Source Traceability** - Every fact links to specific sources
5. **Policy-Driven** - Configurable rules for research decisions
6. **Deterministic Validation** - Plan verification catches issues early
7. **Graceful Degradation** - Handles failures without halting workflow

## Comparison with V1

| Feature | V1 | V2 |
|---------|----|----|
| Planning | Simple query generation | Multi-aspect structured plans |
| Verification | None | Deterministic plan validation |
| Memory | In-memory only | External persistent storage |
| Budget | Manual monitoring | Automated tracking & enforcement |
| Policy | Hardcoded logic | Configurable policy engine |
| Facts | Unstructured | Atomic with confidence scores |
| Parallelism | Sequential | Parallel-capable (future) |
| Artifacts | None | Full JSONL persistence |

## Development

### Running Tests

```bash
cd /path/to/scripts
ruby bin/test
```

Tests cover:
- Model validation (Plan, Fact, Summary, Evaluation)
- Plan verification logic
- Policy engine decision rules
- Token budget tracking
- Artifact storage and retrieval

### Adding New Features

To add a new agent type:

1. Create class in `lib/github_deep_research_agent_v2/`
2. Implement standard interface (if applicable)
3. Add integration point in `Orchestrator`
4. Write tests in `test/lib/github_deep_research_agent_v2/`
5. Update documentation

## Troubleshooting

### Common Issues

**Budget exhausted prematurely**
- Increase `--token-budget`
- Reduce `--max-summaries-per-branch`
- Decrease `--max-depth` or `--breadth`

**Plan validation fails repeatedly**
- Check LLM model quality (use `--reasoning-model` with capable model)
- Review prompt template in `prompts/planner_prompt.txt`
- Enable `--log-level debug` to see validation errors

**Low confidence scores**
- Increase `--max-depth` for deeper investigation
- Add more `--search-modes`
- Lower `--stop-if-confidence` threshold

**Missing dependencies**
- Run `bin/bootstrap` to install tools
- Ensure Qdrant is running and accessible
- Verify `llm` CLI is configured with API keys

## Future Enhancements

- True parallel execution with thread pools
- Semantic similarity with embeddings for relevance ranking
- SQLite backend option for artifact storage
- Replan implementation for gap filling
- Code analysis agent for stack traces
- Metrics agent for performance timelines
- Self-critique evaluation pass
- Hallucination detection with source verification

## License

Same as parent repository.

## Contributing

See CONTRIBUTING.md in repository root.
