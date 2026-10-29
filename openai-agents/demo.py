# Customer-side demo: calls a Semurg node's MCP memory server through the OpenAI Agents SDK's own MCP client.
# No LLM is in the loop: the tools
# are called directly through the framework's tool objects, so what this proves is the framework's MCP client against Semurg.
#   SEMURG_MCP_URL=https://NODE/v1/mcp SEMURG_API_TOKEN=... python demo.py        (token optional on an open node)
# Prints DEMO-VERSION / DEMO-STEP lines and one DEMO-RESULT line; exit 0 PASS, 1 FAIL.
import ast, asyncio, base64, json, os, sys, time, uuid
from importlib.metadata import version, PackageNotFoundError

ID = "openai-agents"
URL = os.environ["SEMURG_MCP_URL"]
TOKEN = os.environ.get("SEMURG_API_TOKEN", "")
RUN = uuid.uuid4().hex[:8]
SCOPE = os.environ.get("SEMURG_MCP_SCOPE") or f"demo-{ID}-{RUN}"
HEADERS = {"X-Semurg-Scope": SCOPE}                       # the node's default scope for this connection
if TOKEN:
    HEADERS["Authorization"] = f"Bearer {TOKEN}"
PERSON, ORG, MENTEE = f"Ada {RUN}", f"Acme {RUN}", f"Bea {RUN}"
FACTS = {"entities": [{"name": PERSON, "type": "person"}, {"name": ORG, "type": "organisation"}],
         "relations": [{"source": PERSON, "target": ORG, "type": "WORKS_AT"}]}
NEED = {"memory_status", "memory_remember", "memory_recall", "memory_relate", "memory_forget", "memory_context", "memory_document"}
KEYS = ("status", "remember", "recall", "context", "relate", "recall2", "document", "docctx", "g7remember", "g7", "miss", "refusal", "forget", "gone")
# G7: the answer QUALITY counts, not only the seven calls: a fact TWO relations out must be an answer.
# Five facts that make a two-relation question, in this run's own scope.
G7_FACTS = {"entities": [{"name": "Priya Raman", "type": "person"}, {"name": "Orion", "type": "project"}, {"name": "Halcyon Labs", "type": "organization"},
                         {"name": "Vega", "type": "library"}, {"name": "Tomas Berg", "type": "person"}],
            "relations": [{"source": "Priya Raman", "target": "Orion", "type": "LEADS"}, {"source": "Orion", "target": "Halcyon Labs", "type": "BELONGS_TO"},
                          {"source": "Orion", "target": "Vega", "type": "DEPENDS_ON"}, {"source": "Tomas Berg", "target": "Vega", "type": "MAINTAINS"},
                          {"source": "Priya Raman", "target": "Tomas Berg", "type": "MENTORS"}]}
G7_Q = "Who maintains the library that Priya's project depends on?"
PROJECT = f"Orion {RUN}"
TEXT = f"{PERSON} works at {ORG} and leads the billing rewrite there."
DOC_B64 = base64.b64encode(f"Meeting notes\n\n{PERSON} approved the {PROJECT} budget on Monday.\n".encode()).decode()
JUNK_B64 = base64.b64encode(bytes(range(64))).decode()   # not a document: the node must refuse it by name


def versions(*pkgs):
    for p in pkgs:
        try:
            print(f"DEMO-VERSION {p} {version(p)}", flush=True)
        except PackageNotFoundError:
            print(f"DEMO-VERSION {p} not-installed", flush=True)


def step(name, ok, detail=""):
    print(f"DEMO-STEP {name} {'ok' if ok else 'FAIL'} {str(detail)[:200]!r}", flush=True)
    return ok


def text(x):
    """Flatten whatever the framework hands back (MCP CallToolResult, content blocks, str, dict) to plain text."""
    c = getattr(x, "content", x)
    if isinstance(c, (list, tuple)):
        t = "\n".join(str(getattr(i, "text", None) or (i.get("text") if isinstance(i, dict) else None) or i) for i in c)
    else:
        t = str(c)
    return ("[isError] " + t) if getattr(x, "isError", False) else t


def parsed(t):
    """The reply as a dict when it is one (JSON, or the Python repr some frameworks hand back), else None."""
    for load in (json.loads, ast.literal_eval):
        try:
            o = load(t)
            return o if isinstance(o, dict) else None
        except (ValueError, SyntaxError, TypeError, MemoryError, RecursionError):
            pass
    return None


def unwrap(o):
    """A framework that hands back the whole MCP result as a dict ({'content': [{'type': 'text', 'text': ...}], 'isError': ...}; Google ADK
    on r11.125): its text and its isError flag; (None, False) for anything else."""
    if isinstance(o, dict) and isinstance(o.get("content"), list) and "ok" not in o:
        return "\n".join(str(i.get("text", "")) for i in o["content"] if isinstance(i, dict)), bool(o.get("isError"))
    return None, False


def payload(t):
    """The node's own reply object: parsed, and taken out of an MCP envelope when the framework returned one."""
    o = parsed(t)
    inner, _ = unwrap(o)
    return parsed(inner) if inner is not None else o


def failed(t):
    """A tool result that says it failed: the MCP isError flag, or a PARSED top-level object with ok false, a truthy error or a refusal
    field. Never the bare word "refused": memory_status carries refused_at_ms / refused_groups counters on an ok:true reply (r11.125
    false-failed every demo on it). Text that is not an object keeps the textual ok:false / error:true check."""
    if not t or t.startswith("[isError]"):
        return True
    o = parsed(t)
    inner, is_error = unwrap(o)
    if inner is not None:
        return is_error or failed(inner)
    if o is not None:
        return o.get("ok") is False or bool(o.get("error")) or bool(o.get("refused")) or bool(o.get("refusal"))
    s = t.replace(" ", "").lower()
    return '"ok":false' in s or "'ok':false" in s or '"error":true' in s or "'error':true" in s


def g7_stored(t):
    """A facts-only remember answers {"ok":true,"mode":"facts","counts":{"relations":N,...}} (no `agent_facts`: that is the content form)."""
    o = payload(t)
    if o is not None:
        return o.get("ok") is True and ((o.get("counts") or {}).get("relations") or 0) >= 5
    return '"relations":5' in t.replace(" ", "")


def g7_answered(t):
    """G7: the reply's facts include Tomas Berg MAINTAINS Vega and Orion DEPENDS_ON Vega (the chain two relations out)."""
    o = payload(t)
    items = (o or {}).get("items") or []
    facts = [(str(i.get("subject", "")), str(i.get("relation", "")), str(i.get("object") or i.get("text") or ""))  # compact: object; full: text
             for i in items if isinstance(i, dict) and i.get("kind") == "fact"]
    if facts:
        return ("Tomas Berg", "MAINTAINS", "Vega") in facts and ("Orion", "DEPENDS_ON", "Vega") in facts
    return "MAINTAINS" in t and "DEPENDS_ON" in t and "Tomas Berg" in t and "Vega" in t


async def scenario(call, tool_names):
    """call(name, args) -> text. The same scenario for every framework: all seven memory tools, text sent WITH its facts, a context
    answer cited to its passage, a document, a name never stored, a refusal by name, forget and its proof. Every call is timed."""
    rt = {}

    async def timed(name, args):
        t0 = time.perf_counter()
        try:
            out = await call(name, args)
        except Exception as e:  # a framework that raises on an MCP error result: keep its text, the step judges it
            out = f"[isError] {type(e).__name__}: {e}"
        print(f"DEMO-TIME {name} {(time.perf_counter() - t0) * 1000:.1f}", flush=True)
        return out

    try:
        if not step("tools/list has the seven memory tools", NEED <= set(tool_names), sorted(tool_names)):
            return False
        st = await timed("memory_status", {})
        rt["status"] = step("memory_status", not failed(st), st)
        rm = await timed("memory_remember", {"content": TEXT, "facts": FACTS, "source": f"agent-demo/{ID}"})
        rt["remember"] = step("memory_remember (text + two entities + a WORKS_AT relation)", "agent_facts" in rm and not failed(rm), rm)
        rc = await timed("memory_recall", {"subject": PERSON})
        rt["recall"] = step(f"memory_recall({PERSON!r}) names {ORG!r}", ORG in rc and not failed(rc), rc)
        cx = await timed("memory_context", {"query": f"Where does {PERSON} work?"})
        rt["context"] = step("memory_context returns the passage with its citation", "billing rewrite" in cx and "citation" in cx and not failed(cx), cx)
        rl = await timed("memory_relate", {"from": PERSON, "to": MENTEE, "type": "MENTORS"})
        rt["relate"] = step(f"memory_relate({PERSON!r} MENTORS {MENTEE!r})", bool(rl) and not failed(rl), rl)
        rc2 = await timed("memory_recall", {"subject": PERSON})
        rt["recall2"] = step(f"memory_recall again names the new edge {MENTEE!r}", MENTEE in rc2 and not failed(rc2), rc2)
        dc = await timed("memory_document", {"content_base64": DOC_B64, "name": f"notes-{RUN}.txt"})
        rt["document"] = step("memory_document stores a text file", "doc_id" in dc and not failed(dc), dc)
        dx = await timed("memory_context", {"query": f"What did {PERSON} approve?"})
        rt["docctx"] = step(f"memory_context finds the document's passage ({PROJECT!r})", PROJECT in dx and not failed(dx), dx)
        g7r = await timed("memory_remember", {"facts": G7_FACTS, "source": f"agent-demo/{ID}/g7"})
        rt["g7remember"] = step("memory_remember (G7: five entities, five relations)", g7_stored(g7r) and not failed(g7r), g7r)
        g7 = await timed("memory_context", {"query": G7_Q, "k": 8, "hops": 2})
        rt["g7"] = step("G7: a two-relation question names Tomas Berg MAINTAINS Vega and Orion DEPENDS_ON Vega", g7_answered(g7) and not failed(g7), g7)
        ms = await timed("memory_recall", {"subject": f"Nobody {RUN}"})
        rt["miss"] = step("a name never stored answers nothing_stored", "nothing_stored" in ms and not failed(ms), ms)
        rf = await timed("memory_document", {"content_base64": JUNK_B64, "name": "junk.bin"})
        rt["refusal"] = step("a file that is not a document is refused by name", failed(rf) and "document_unsupported_kind" in rf, rf)
        fg = await timed("memory_forget", {"subject": PERSON, "reason": f"agent-demo/{ID} cleanup"})
        rt["forget"] = step(f"memory_forget({PERSON!r})", bool(fg) and not failed(fg), fg)
        gn = await timed("memory_recall", {"subject": PERSON})
        rt["gone"] = step(f"after forget, memory_recall({PERSON!r}) answers nothing_stored", "nothing_stored" in gn and not failed(gn), gn)
        return all(rt.get(k) for k in KEYS)
    finally:
        print("DEMO-ROUNDTRIP " + " ".join(f"{k}={'ok' if rt.get(k) else 'FAIL'}" for k in KEYS), flush=True)


def finish(ok, detail=""):
    print(f"DEMO-RESULT {ID} {'PASS' if ok else 'FAIL'} scope={SCOPE} {detail}", flush=True)
    sys.exit(0 if ok else 1)



from agents.mcp import MCPServerStreamableHttp  # snippet


async def main():
    versions("openai-agents", "mcp")
    async with MCPServerStreamableHttp(name="semurg", params={"url": URL, "headers": HEADERS, "timeout": 20},  # snippet
                                       client_session_timeout_seconds=30) as server:  # snippet
        tools = await server.list_tools()  # snippet

        async def call(name, args):
            return text(await server.call_tool(name, args))

        ok = await scenario(call, [t.name for t in tools])
    finish(ok)


asyncio.run(main())
