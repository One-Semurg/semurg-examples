# Run: python snippet.py   (SEMURG_API_TOKEN must be set in the environment)
import asyncio, os
from agent_framework import MCPStreamableHTTPTool

URL = os.environ.get("SEMURG_MCP_URL", "http://127.0.0.1:4000/v1/mcp")
HEADERS = {"Authorization": "Bearer " + os.environ["SEMURG_API_TOKEN"],
           "X-Semurg-Scope": os.environ.get("SEMURG_MCP_SCOPE", "default")}
FACTS = {"entities": [{"name": "Ada", "type": "person"}, {"name": "Acme", "type": "organisation"}],
         "relations": [{"source": "Ada", "target": "Acme", "type": "WORKS_AT"}]}


async def main():
    async with MCPStreamableHTTPTool(name="semurg", url=URL, static_headers=HEADERS) as mcp:
        by = {f.name: f for f in mcp.functions}
        await by["memory_remember"].invoke(facts=FACTS)
        result = await by["memory_recall"].invoke(subject="Ada")
        print("\n".join(getattr(c, "text", None) or str(c) for c in (result if isinstance(result, (list, tuple)) else [result])))


asyncio.run(main())
