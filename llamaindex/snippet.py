# Run: python snippet.py   (SEMURG_API_TOKEN must be set in the environment)
import asyncio, os
from llama_index.tools.mcp import BasicMCPClient, McpToolSpec

URL = os.environ.get("SEMURG_MCP_URL", "http://127.0.0.1:4000/v1/mcp")
HEADERS = {"Authorization": "Bearer " + os.environ["SEMURG_API_TOKEN"],
           "X-Semurg-Scope": os.environ.get("SEMURG_MCP_SCOPE", "default")}
FACTS = {"entities": [{"name": "Ada", "type": "person"}, {"name": "Acme", "type": "organisation"}],
         "relations": [{"source": "Ada", "target": "Acme", "type": "WORKS_AT"}]}


async def main():
    client = BasicMCPClient(URL, headers=HEADERS)
    by = {t.metadata.name: t for t in await McpToolSpec(client=client).to_tool_list_async()}
    await by["memory_remember"].acall(facts=FACTS)
    print(await by["memory_recall"].acall(subject="Ada"))


asyncio.run(main())
