// Run: npx tsx snippet.ts   (SEMURG_API_TOKEN must be set in the environment)
import { createMCPClient } from "@ai-sdk/mcp";

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
  const client = await createMCPClient({ transport: { type: "http", url, headers } });
  try {
    const tools: Record<string, any> = await client.tools();
    const opts = { toolCallId: "1", messages: [] };
    await tools["memory_remember"].execute({ facts }, opts);
    console.log(JSON.stringify(await tools["memory_recall"].execute({ subject: "Ada" }, opts)));
  } finally {
    await client.close();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
