// Customer-side demo: calls a Semurg node's MCP memory server through Mastra's own MCP client.
// No LLM is in the loop: the tools
// are called directly through the framework's tool objects, so what this proves is the framework's MCP client against Semurg.
//   SEMURG_MCP_URL=https://NODE/v1/mcp SEMURG_API_TOKEN=... npx tsx demo.ts       (token optional on an open node)
// Prints DEMO-VERSION / DEMO-STEP lines and one DEMO-RESULT line; exit 0 PASS, 1 FAIL.
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

const ID = "mastra";
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
const KEYS = ["status", "remember", "recall", "context", "relate", "recall2", "document", "docctx", "g7remember", "g7", "miss", "refusal", "forget", "gone"];
// G7: the answer QUALITY counts, not only the seven calls: a fact TWO relations out must be an answer.
// Five facts that make a two-relation question, in this run's own scope.
const G7_FACTS = {
  entities: [{ name: "Priya Raman", type: "person" }, { name: "Orion", type: "project" }, { name: "Halcyon Labs", type: "organization" },
             { name: "Vega", type: "library" }, { name: "Tomas Berg", type: "person" }],
  relations: [{ source: "Priya Raman", target: "Orion", type: "LEADS" }, { source: "Orion", target: "Halcyon Labs", type: "BELONGS_TO" },
              { source: "Orion", target: "Vega", type: "DEPENDS_ON" }, { source: "Tomas Berg", target: "Vega", type: "MAINTAINS" },
              { source: "Priya Raman", target: "Tomas Berg", type: "MENTORS" }],
};
const G7_Q = "Who maintains the library that Priya's project depends on?";
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
/** The reply as an object when it is one (JSON), else null. */
function parsed(t: string): Record<string, any> | null {
  try { const o = JSON.parse(t); return o && typeof o === "object" && !Array.isArray(o) ? o : null; } catch { return null; }
}
/** A tool result that says it failed: the MCP isError flag, or a PARSED top-level object with ok false, a truthy error or a refusal field.
 *  Never the bare word "refused": memory_status carries refused_at_ms / refused_groups counters on an ok:true reply (r11.125 false-failed
 *  every demo on it). Text that is not an object keeps the textual ok:false / error:true check. */
function failed(t: string): boolean {
  if (!t || t.startsWith("[isError]")) return true;
  const o = parsed(t);
  if (o) return o.ok === false || !!o.error || !!o.refused || !!o.refusal;
  const s = t.replace(/ /g, "").toLowerCase();
  return s.includes('"ok":false') || s.includes('"error":true');
}
/** A facts-only remember answers {"ok":true,"mode":"facts","counts":{"relations":N,...}} (no agent_facts: that is the content form). */
function g7Stored(t: string): boolean {
  const o = parsed(t);
  return o ? o.ok === true && (o.counts?.relations ?? 0) >= 5 : t.replace(/ /g, "").includes('"relations":5');
}
/** G7: the reply's facts include Tomas Berg MAINTAINS Vega and Orion DEPENDS_ON Vega (the chain two relations out). */
function g7Answered(t: string): boolean {
  const items: any[] = parsed(t)?.items ?? [];
  const facts = items.filter((i) => i && i.kind === "fact").map((i) => `${i.subject}|${i.relation}|${i.object ?? i.text ?? ""}`);  // compact: object; full: text
  if (facts.length) return facts.includes("Tomas Berg|MAINTAINS|Vega") && facts.includes("Orion|DEPENDS_ON|Vega");
  return t.includes("MAINTAINS") && t.includes("DEPENDS_ON") && t.includes("Tomas Berg") && t.includes("Vega");
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
    const g7r = await timed("memory_remember", { facts: G7_FACTS, source: `agent-demo/${ID}/g7` });
    rt.g7remember = step("memory_remember (G7: five entities, five relations)", g7Stored(g7r) && !failed(g7r), g7r);
    const g7 = await timed("memory_context", { query: G7_Q, k: 8, hops: 2 });
    rt.g7 = step("G7: a two-relation question names Tomas Berg MAINTAINS Vega and Orion DEPENDS_ON Vega", g7Answered(g7) && !failed(g7), g7);
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


import { MCPClient } from "@mastra/mcp";  // snippet

versions("@mastra/mcp", "@mastra/core");
const mcp = new MCPClient({ servers: { semurg: { url: new URL(URL_), requestInit: { headers: HEADERS } } } });  // snippet
try {
  const tools: Record<string, any> = await mcp.listTools();          // Mastra namespaces them: semurg_memory_status ...  // snippet
  const byName: Record<string, any> = {};
  for (const [k, t] of Object.entries(tools)) byName[k.replace(/^semurg_/, "")] = t;
  const call = async (name: string, args: object) => text(await byName[name].execute(args, {}));
  finish(await scenario(call, Object.keys(byName)));
} catch (e: any) {
  step("mastra run", false, e?.stack ?? e);
  finish(false, "exception");
} finally {
  await mcp.disconnect();
}
