# Run: python snippet.py   (SEMURG_API_TOKEN must be set in the environment)
import asyncio, os
from agents.mcp import MCPServerStreamableHttp

URL = os.environ.get("SEMURG_MCP_URL", "http://127.0.0.1:4000/v1/mcp")
HEADERS = {"Authorization": "Bearer " + os.environ["SEMURG_API_TOKEN"],
           "X-Semurg-Scope": os.environ.get("SEMURG_MCP_SCOPE", "default")}
FACTS = {"entities": [{"name": "Ada", "type": "person"}, {"name": "Acme", "type": "organisation"}],
         "relations": [{"source": "Ada", "target": "Acme", "type": "WORKS_AT"}]}


async def main():
    async with MCPServerStreamableHttp(name="semurg", params={"url": URL, "headers": HEADERS, "timeout": 20},
                                       client_session_timeout_seconds=30) as server:
        await server.call_tool("memory_remember", {"facts": FACTS})
        print(await server.call_tool("memory_recall", {"subject": "Ada"}))


asyncio.run(main())
