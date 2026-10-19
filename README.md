# Semurg memory examples

Runnable programs that give an AI agent framework Semurg as its memory: the seven memory tools (status, remember, recall,
relate, forget, context, document) over MCP or plain HTTP, against a Semurg node you run yourself.

Each program runs twelve checked steps against a fresh node and prints the time of every call. The table says which release
it last ran on, with which package versions, and the sha256 of the file that ran: the file in this repository is that file.

Install a node: https://one.semurg.io/install (Intel and AMD x86_64 with AVX2 or newer: Linux, or Windows through WSL2 or
Docker; no Mac or ARM build yet). Every tool, route and call: https://one.semurg.io/llms.txt

Run one:

    export SEMURG_MCP_URL=http://127.0.0.1:4000/v1/mcp
    export SEMURG_API_TOKEN=<the token your node printed at install>
    cd langchain && pip install -r requirements.txt && python demo.py

| Framework | Status on r11.115.20261018.0598d3b | Packages | File sha256 (first 16) |
|---|---|---|---|
| crewai | ran end to end | crewai=1.15.28, crewai-tools=1.15.28, mcp=1.28.1 | `d151f4408e71231b` |
| elixir-langchain | ran end to end | langchain=0.4.1, langchain_mcp=0.2.0, anubis_mcp=0.16.0, plug=1.20.3 | `d3cd8e36c0dcd2be` |
| google-adk | ran end to end | google-adk=2.12.0, mcp=1.30.0 | `d9ed0040ff9dea70` |
| jido | ran end to end | jido=2.4.0, jido_action=2.4.0, req=0.7.5 | `089f931bd2951386` |
| langchain | ran end to end | langchain-mcp-adapters=0.3.2, langchain-core=1.6.12, mcp=1.30.0 | `84aec7125a20f4dc` |
| llamaindex | ran end to end | llama-index-tools-mcp=0.6.0, llama-index-core=0.14.25, mcp=2.3.0 | `82828435aba9215c` |
| mastra | ran end to end | @mastra/mcp=2.4.1, @mastra/core=1.78.0 | `8cedebd91ce34fa7` |
| msagent | ran end to end | agent-framework=1.22.0, agent-framework-core=1.22.0, mcp=1.30.0 | `942bc19a70079995` |
| openai-agents | ran end to end | openai-agents=0.24.0, mcp=2.3.0 | `fbd38b1b6ea983fd` |
| pydantic-ai | ran end to end | pydantic-ai-slim=2.57.0, mcp=2.3.0 | `3c2b557db70872d5` |
| vercel-ai | ran end to end | ai=7.0.143, @ai-sdk/mcp=2.0.78 | `e7a50461890e9699` |

Questions, results on your own machine, or a framework you want here: https://one.semurg.io/contact
