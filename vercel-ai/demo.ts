// Customer-side demo: calls a Semurg node's MCP memory server through the Vercel AI SDK's own MCP client. Part of the fenced examples
// directory (scripts/ci/agent_examples_fence.sh): never imported, built or shipped by the product. No LLM is in the loop: the tools
// are called directly through the framework's tool objects, so what this proves is the framework's MCP client against Semurg.
//   SEMURG_MCP_URL=https://NODE/v1/mcp SEMURG_API_TOKEN=... npx tsx demo.ts       (token optional on an open node)
// Prints DEMO-VERSION / DEMO-STEP lines and one DEMO-RESULT line; exit 0 PASS, 1 FAIL.
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

const ID = "vercel-ai";
const URL_ = process.env.SEMURG_MCP_URL!;
const TOKEN = process.env.SEMURG_API_TOKEN ?? "";
const RUN = randomUUID().slice(0, 8);
const SCOPE = process.env.SEMURG_MCP_SCOPE ?? `demo-${ID}-${RUN}`;
const HEADERS: Record<string, string> = { "X-Semurg-Scope": SCOPE };   // the node's default scope for this connection
if (TOKEN) HEADERS["Authorization"] = `Bearer ${TOKEN}`;
const PERSON = `Ada ${RUN}`, ORG = `Acme ${RUN}`, MENTEE = `Bea ${RUN}`;
const FACTS = {
  entities: [{ name: PERSON, type: "person" }, { name: ORG, type: "organisation" }],
  relations: [{ source: PERSON, target: ORG, type: "WORKS_AT" }],
};
const NEED = ["memory_status", "memory_remember", "memory_recall", "memory_relate", "memory_forget", "memory_context", "memory_document"];
const KEYS = ["status", "remember", "recall", "context", "relate", "recall2", "document", "docctx", "miss", "refusal", "forget", "gone"];
const PROJECT = `Orion ${RUN}`;
const TEXT = `${PERSON} works at ${ORG} and leads the billing rewrite there.`;
const DOC_B64 = Buffer.from(`Meeting notes\n\n${PERSON} approved the ${PROJECT} budget on Monday.\n`).toString("base64");
const JUNK_B64 = Buffer.from(Array.from({ length: 64 }, (_, i) => i)).toString("base64");   // not a document: refused by name

function versions(...pkgs: string[]) {
  for (const p of pkgs) {
    try { console.log(`DEMO-VERSION ${p} ${JSON.parse(readFileSync(`node_modules/${p}/package.json`, "utf8")).version}`); }
    catch { console.log(`DEMO-VERSION ${p} not-installed`); }
  }
}
function step(name: string, ok: boolean, detail: unknown = ""): boolean {
  console.log(`DEMO-STEP ${name} ${ok ? "ok" : "FAIL"} ${JSON.stringify(String(typeof detail === "string" ? detail : JSON.stringify(detail)).slice(0, 200))}`);
  return ok;
}
/** Flatten whatever the framework hands back (MCP result, content blocks, string, object) to plain text. */
function text(x: any): string {
  const c = x?.content ?? x;
  const t = Array.isArray(c) ? c.map((i) => (typeof i === "string" ? i : i?.text ?? JSON.stringify(i))).join("\n") : typeof c === "string" ? c : JSON.stringify(c);
  return x?.isError ? "[isError] " + t : t;
}
/** A tool result that says it failed: the MCP isError flag, an ok:false body, or a refusal. */
function failed(t: string): boolean {
  const s = t.replace(/ /g, "").toLowerCase();
  return !t || t.startsWith("[isError]") || s.includes('"ok":false') || s.includes('"error":true') || s.includes("refused");
}
/** The same scenario for every framework: all seven memory tools, text sent WITH its facts, a context answer cited to its passage, a
 *  document, a name never stored, a refusal by name, forget and its proof. Every call is timed (DEMO-TIME <tool> <ms>). */
async function scenario(call: (name: string, args: object) => Promise<string>, toolNames: string[]): Promise<boolean> {
  const rt: Record<string, boolean> = {};
  const timed = async (name: string, args: object): Promise<string> => {
    const t0 = performance.now();
    let out: string;
    try { out = await call(name, args); }
    catch (e: any) { out = `[isError] ${e?.name ?? "Error"}: ${e?.message ?? e}`; }   // a framework that throws on an MCP error result
    console.log(`DEMO-TIME ${name} ${(performance.now() - t0).toFixed(1)}`);
    return out;
  };
  const q = JSON.stringify;
  try {
    if (!step("tools/list has the seven memory tools", NEED.every((n) => toolNames.includes(n)), toolNames.sort())) return false;
    const st = await timed("memory_status", {});
    rt.status = step("memory_status", !failed(st), st);
    const rm = await timed("memory_remember", { content: TEXT, facts: FACTS, source: `agent-demo/${ID}` });
    rt.remember = step("memory_remember (text + two entities + a WORKS_AT relation)", rm.includes("agent_facts") && !failed(rm), rm);
    const rc = await timed("memory_recall", { subject: PERSON });
    rt.recall = step(`memory_recall(${q(PERSON)}) names ${q(ORG)}`, rc.includes(ORG) && !failed(rc), rc);
    const cx = await timed("memory_context", { query: `Where does ${PERSON} work?` });
    rt.context = step("memory_context returns the passage with its citation", cx.includes("billing rewrite") && cx.includes("citation") && !failed(cx), cx);
    const rl = await timed("memory_relate", { from: PERSON, to: MENTEE, type: "MENTORS" });
    rt.relate = step(`memory_relate(${q(PERSON)} MENTORS ${q(MENTEE)})`, rl.length > 0 && !failed(rl), rl);
    const rc2 = await timed("memory_recall", { subject: PERSON });
    rt.recall2 = step(`memory_recall again names the new edge ${q(MENTEE)}`, rc2.includes(MENTEE) && !failed(rc2), rc2);
    const dc = await timed("memory_document", { content_base64: DOC_B64, name: `notes-${RUN}.txt` });
    rt.document = step("memory_document stores a text file", dc.includes("doc_id") && !failed(dc), dc);
    const dx = await timed("memory_context", { query: `What did ${PERSON} approve?` });
    rt.docctx = step(`memory_context finds the document's passage (${q(PROJECT)})`, dx.includes(PROJECT) && !failed(dx), dx);
    const ms = await timed("memory_recall", { subject: `Nobody ${RUN}` });
    rt.miss = step("a name never stored answers nothing_stored", ms.includes("nothing_stored") && !failed(ms), ms);
    const rf = await timed("memory_document", { content_base64: JUNK_B64, name: "junk.bin" });
    rt.refusal = step("a file that is not a document is refused by name", failed(rf) && rf.includes("document_unsupported_kind"), rf);
    const fg = await timed("memory_forget", { subject: PERSON, reason: `agent-demo/${ID} cleanup` });
    rt.forget = step(`memory_forget(${q(PERSON)})`, fg.length > 0 && !failed(fg), fg);
    const gn = await timed("memory_recall", { subject: PERSON });
    rt.gone = step(`after forget, memory_recall(${q(PERSON)}) answers nothing_stored`, gn.includes("nothing_stored") && !failed(gn), gn);
    return KEYS.every((k) => rt[k]);
  } finally {
    console.log("DEMO-ROUNDTRIP " + KEYS.map((k) => `${k}=${rt[k] ? "ok" : "FAIL"}`).join(" "));
  }
}
function finish(ok: boolean, detail = ""): never {
  console.log(`DEMO-RESULT ${ID} ${ok ? "PASS" : "FAIL"} scope=${SCOPE} ${detail}`);
  process.exit(ok ? 0 : 1);
}


// the MCP client moved packages between AI SDK majors: prefer @ai-sdk/mcp, fall back to the experimental export of `ai`
let createMCPClient: any;
try { ({ createMCPClient } = await import("@ai-sdk/mcp" as string)); }
catch { ({ experimental_createMCPClient: createMCPClient } = await import("ai")); }

versions("ai", "@ai-sdk/mcp", "@modelcontextprotocol/sdk");
const client = await createMCPClient({ transport: { type: "http", url: URL_, headers: HEADERS } });  // snippet
try {
  const tools: Record<string, any> = await client.tools();  // snippet
  const call = async (name: string, args: object) => text(await tools[name].execute(args, { toolCallId: "demo", messages: [] }));
  finish(await scenario(call, Object.keys(tools)));
} catch (e: any) {
  step("vercel-ai run", false, e?.stack ?? e);
  finish(false, "exception");
} finally {
  await client.close();
}
