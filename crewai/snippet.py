# Run: python snippet.py   (SEMURG_API_TOKEN must be set in the environment)
import os
from crewai_tools import MCPServerAdapter

URL = os.environ.get("SEMURG_MCP_URL", "http://127.0.0.1:4000/v1/mcp")
HEADERS = {"Authorization": "Bearer " + os.environ["SEMURG_API_TOKEN"],
           "X-Semurg-Scope": os.environ.get("SEMURG_MCP_SCOPE", "default")}
FACTS = {"entities": [{"name": "Ada", "type": "person"}, {"name": "Acme", "type": "organisation"}],
         "relations": [{"source": "Ada", "target": "Acme", "type": "WORKS_AT"}]}

params = {"url": URL, "transport": "streamable-http", "headers": HEADERS}
with MCPServerAdapter(params, connect_timeout=60) as tools:
    by = {t.name: t for t in tools}
    by["memory_remember"].run(facts=FACTS)
    print(by["memory_recall"].run(subject="Ada"))
