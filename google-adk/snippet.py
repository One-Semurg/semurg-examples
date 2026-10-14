# Run: python snippet.py   (SEMURG_API_TOKEN must be set in the environment)
import asyncio, os
from google.adk.tools.mcp_tool.mcp_toolset import McpToolset, StreamableHTTPConnectionParams

URL = os.environ.get("SEMURG_MCP_URL", "http://127.0.0.1:4000/v1/mcp")
HEADERS = {"Authorization": "Bearer " + os.environ["SEMURG_API_TOKEN"],
           "X-Semurg-Scope": os.environ.get("SEMURG_MCP_SCOPE", "default")}
FACTS = {"entities": [{"name": "Ada", "type": "person"}, {"name": "Acme", "type": "organisation"}],
         "relations": [{"source": "Ada", "target": "Acme", "type": "WORKS_AT"}]}


async def main():
    toolset = McpToolset(connection_params=StreamableHTTPConnectionParams(url=URL, headers=HEADERS))
    try:
        by = {t.name: t for t in await toolset.get_tools()}
        await by["memory_remember"].run_async(args={"facts": FACTS}, tool_context=None)
        print(await by["memory_recall"].run_async(args={"subject": "Ada"}, tool_context=None))
    finally:
        await toolset.close()


asyncio.run(main())
