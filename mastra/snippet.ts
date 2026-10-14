// Run: npx tsx snippet.ts   (SEMURG_API_TOKEN must be set in the environment)
import { MCPClient } from "@mastra/mcp";

const url = process.env.SEMURG_MCP_URL ?? "http://127.0.0.1:4000/v1/mcp";
const headers = {
  Authorization: `Bearer ${process.env.SEMURG_API_TOKEN}`,
  "X-Semurg-Scope": process.env.SEMURG_MCP_SCOPE ?? "default",
};
const facts = {
  entities: [{ name: "Ada", type: "person" }, { name: "Acme", type: "organisation" }],
  relations: [{ source: "Ada", target: "Acme", type: "WORKS_AT" }],
};

async function main() {
  const mcp = new MCPClient({ servers: { semurg: { url: new URL(url), requestInit: { headers } } } });
  try {
    const tools: Record<string, any> = await mcp.listTools(); // Mastra prefixes each tool with the server name
    await tools["semurg_memory_remember"].execute({ facts }, {});
    console.log(JSON.stringify(await tools["semurg_memory_recall"].execute({ subject: "Ada" }, {})));
  } finally {
    await mcp.disconnect();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
