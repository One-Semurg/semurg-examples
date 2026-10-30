# Semurg memory examples

Runnable programs that give an AI agent framework Semurg as its memory: the nine memory tools (remember, document, recall,
relate, forget, context, status, export and import) over MCP or plain HTTP, against a Semurg node you run yourself.

Each program runs its checked steps against a fresh node and prints the time of every call. The table says which release
it last ran on, with which package versions, and the sha256 of the file that ran: the file in this repository is that file.

Install a node (requirements and supported systems): https://one.semurg.io/install. Every tool, route and call:
https://one.semurg.io/llms.txt

Run one:

    export SEMURG_MCP_URL=http://127.0.0.1:4000/v1/mcp
    # the API token is never printed; read it into your shell (the installer's SUCCESS banner shows this line):
    export SEMURG_API_TOKEN="$(sudo grep '^SEMURG_API_TOKEN=' /etc/semurg/semurg.env | cut -d= -f2-)"
    # a node in Docker: export SEMURG_API_TOKEN="$(docker exec semurg cat /var/lib/semurg/.api_token)"
    cd langchain && pip install -r requirements.txt && python demo.py

| Framework | Status on r11.139.20261030.0186d91 | Packages | File sha256 (first 16) |
|---|---|---|---|
| crewai | ran end to end | crewai=1.15.33, crewai-tools=1.15.33, mcp=1.30.0 | `a7c4ba6179ccb1c8` |
| elixir-langchain | ran end to end | langchain=0.4.1, langchain_mcp=0.2.0, anubis_mcp=0.16.0, plug=1.20.3 | `17de712573e4ad60` |
| google-adk | ran end to end | google-adk=2.13.0, mcp=1.30.0 | `088b238d42a61df1` |
| jido | ran end to end | jido=2.4.0, jido_action=2.4.0, req=0.7.5 | `cec6c15c9cc9bbbf` |
| langchain | ran end to end | langchain-mcp-adapters=0.3.2, langchain-core=1.7.3, mcp=1.30.0 | `69e8fb91b11292e6` |
| llamaindex | ran end to end | llama-index-tools-mcp=0.6.0, llama-index-core=0.14.25, mcp=2.3.0 | `f9f9f34446496bcf` |
| mastra | ran end to end | @mastra/mcp=2.6.0, @mastra/core=1.80.0 | `bc2cd9e032bfabd1` |
| msagent | ran end to end | agent-framework=1.23.0, agent-framework-core=1.23.0, mcp=2.3.0 | `5eb91a2405a68b05` |
| openai-agents | ran end to end | openai-agents=0.24.0, mcp=2.3.0 | `788d37f70593ac70` |
| pydantic-ai | ran end to end | pydantic-ai-slim=2.63.0, mcp=2.3.0 | `c8cd1ba1ce797995` |
| vercel-ai | ran end to end | ai=7.0.157, @ai-sdk/mcp=2.0.87 | `d47513cdb9b88e2e` |

Questions, results on your own machine, or a framework you want here: https://one.semurg.io/contact
