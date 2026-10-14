# Run: python snippet.py   (SEMURG_API_TOKEN must be set in the environment)
import asyncio, os
from langchain_mcp_adapters.client import MultiServerMCPClient

URL = os.environ.get("SEMURG_MCP_URL", "http://127.0.0.1:4000/v1/mcp")
HEADERS = {"Authorization": "Bearer " + os.environ["SEMURG_API_TOKEN"],
           "X-Semurg-Scope": os.environ.get("SEMURG_MCP_SCOPE", "default")}
FACTS = {"entities": [{"name": "Ada", "type": "person"}, {"name": "Acme", "type": "organisation"}],
         "relations": [{"source": "Ada", "target": "Acme", "type": "WORKS_AT"}]}


async def main():
    client = MultiServerMCPClient({"semurg": {"url": URL, "transport": "streamable_http", "headers": HEADERS}})
    tools = {t.name: t for t in await client.get_tools()}
    await tools["memory_remember"].ainvoke({"facts": FACTS})
    print(await tools["memory_recall"].ainvoke({"subject": "Ada"}))


asyncio.run(main())
