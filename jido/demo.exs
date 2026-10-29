# Customer-side demo: Semurg's seven memory tools as Jido Actions, run by a Jido agent.
# No LLM is in the loop: the Actions are run
# directly (Jido.Exec.run/2 and the agent's cmd/2), so what this proves is Jido's own action and agent code against Semurg. Jido's
# MCP package (jido_mcp) is deprecated, so the Actions call the node's HTTP memory API: the same six calls the MCP tools make.
#   SEMURG_MCP_URL=https://NODE/v1/mcp SEMURG_API_TOKEN=... elixir demo.exs        (token optional on an open node)
#   DEMO_INSTALL_ONLY=1 elixir demo.exs       fetch and compile the packages, then stop (the runner's phase 1: no token, no url)
# Prints DEMO-VERSION / DEMO-STEP lines and one DEMO-RESULT line; exit 0 PASS, 1 FAIL.
Mix.install([{:jido, "~> 2.0"}, {:jido_action, "~> 2.0"}, {:req, "~> 0.5"}])

id = "jido"
vsn = fn app -> if v = Application.spec(app, :vsn), do: to_string(v), else: "not-installed" end
for app <- [:jido, :jido_action, :req], do: IO.puts("DEMO-VERSION #{app} #{vsn.(app)}")
if System.get_env("DEMO_INSTALL_ONLY") == "1", do: System.halt(0)

run_id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
scope = System.get_env("SEMURG_MCP_SCOPE") || "demo-#{id}-#{run_id}"
System.put_env("SEMURG_MCP_SCOPE", scope)
person = "Ada #{run_id}"
org = "Acme #{run_id}"
mentee = "Bea #{run_id}"

defmodule SemurgNode do
  @moduledoc false
  # the node's address and credentials, read from the environment; the scope header is the node's default scope for this connection
  def base, do: System.fetch_env!("SEMURG_MCP_URL") |> String.replace_suffix("/v1/mcp", "")

  def headers do
    token = System.get_env("SEMURG_API_TOKEN") || ""
    [{"x-semurg-scope", System.get_env("SEMURG_MCP_SCOPE") || "demo-jido"}] ++
      if(token == "", do: [], else: [{"authorization", "Bearer " <> token}])
  end

  # ONE APP, MANY END USERS: every Action takes the end user's user_id (and a scope) and passes it through, so each end user's memory is
  # their own and two never meet. A call without them uses this connection's scope and no user. An unset key is dropped (the node
  # refuses a user_id of null).
  def given(params), do: for({k, v} <- params, v != nil, into: %{}, do: {k, v})

  def status(params), do: handle(Req.get(base() <> "/v1/memory/status", params: Enum.to_list(given(params)), headers: headers(), retry: false))

  def post(call, body),
    do: handle(Req.post(base() <> "/v1/memory/" <> call, json: Map.put_new(given(body), :scope, System.get_env("SEMURG_MCP_SCOPE") || "demo-jido"), headers: headers(), retry: false))   # the HTTP routes read the scope and the user from the BODY (the X-Semurg-Scope header is the MCP door's connection default)

  defp handle({:ok, %Req.Response{status: s, body: b}}) when s in 200..299, do: {:ok, %{answer: b}}
  # the refusal's NAME first (a refusal body carries `refusal`, e.g. document_unsupported_kind): it is what a caller branches on, and
  # leading with it keeps it readable even where an error wrapper shortens the message (the r11.86 run: the name was lost in the tail)
  defp handle({:ok, %Req.Response{status: s, body: %{"refusal" => r} = b}}), do: {:error, "HTTP #{s} #{r}: #{text(b)}"}
  defp handle({:ok, %Req.Response{status: s, body: b}}), do: {:error, "HTTP #{s}: #{text(b)}"}
  defp handle({:error, e}), do: {:error, Exception.message(e)}

  def text(b) when is_binary(b), do: b
  def text(b), do: inspect(b, limit: :infinity, printable_limit: :infinity)
end

defmodule SemurgDemo.Status do
  use Jido.Action, name: "memory_status", description: "Report whether shared memory is on for this node and which of YOUR scopes hold facts", schema: [scope: [type: :string], user_id: [type: :string]]
  @impl true
  def run(params, _context), do: SemurgNode.status(Map.take(params, [:scope, :user_id]))
end

defmodule SemurgDemo.Remember do
  use Jido.Action, name: "memory_remember", description: "Store facts in shared agent memory", schema: [facts: [type: :map, required: true], content: [type: :string], source: [type: :string], scope: [type: :string], user_id: [type: :string]]  # snippet
  @impl true
  def run(params, _context), do: SemurgNode.post("remember", Map.take(params, [:facts, :content, :source, :scope, :user_id]))
end

defmodule SemurgDemo.Recall do
  use Jido.Action, name: "memory_recall", description: "Recall what is stored about ONE entity", schema: [subject: [type: :string, required: true], k: [type: :integer], scope: [type: :string], user_id: [type: :string]]
  @impl true
  def run(params, _context), do: SemurgNode.post("recall", Map.take(params, [:subject, :k, :scope, :user_id]))
end

defmodule SemurgDemo.Relate do
  use Jido.Action, name: "memory_relate", description: "Add ONE typed edge between two entities in a scope", schema: [from: [type: :string, required: true], to: [type: :string, required: true], type: [type: :string, required: true], scope: [type: :string], user_id: [type: :string]]
  @impl true
  def run(params, _context), do: SemurgNode.post("relate", Map.take(params, [:from, :to, :type, :scope, :user_id]))
end

defmodule SemurgDemo.Forget do
  use Jido.Action, name: "memory_forget", description: "Mark an entity as superseded in a scope", schema: [subject: [type: :string, required: true], reason: [type: :string], scope: [type: :string], user_id: [type: :string]]
  @impl true
  def run(params, _context), do: SemurgNode.post("forget", Map.take(params, [:subject, :reason, :scope, :user_id]))
end

defmodule SemurgDemo.Context do
  use Jido.Action, name: "memory_context", description: "Retrieve what the memory holds that is relevant to a question", schema: [query: [type: :string, required: true], hops: [type: :integer], k: [type: :integer], scope: [type: :string], user_id: [type: :string]]
  @impl true
  def run(params, _context), do: SemurgNode.post("context", Map.take(params, [:query, :hops, :k, :scope, :user_id]))
end

defmodule SemurgDemo.Document do
  use Jido.Action, name: "memory_document", description: "Store a document (a PDF, a Word .docx, an HTML page or a UTF-8 text file) as memory", schema: [content_base64: [type: :string, required: true], name: [type: :string], scope: [type: :string], user_id: [type: :string]]
  @impl true
  def run(params, _context), do: SemurgNode.post("document", Map.take(params, [:content_base64, :name, :scope, :user_id]))
end

defmodule SemurgDemo.MemoryAgent do
  use Jido.Agent, name: "semurg_memory", description: "An agent whose memory is a Semurg node", schema: [answer: [type: :any, default: nil]]
end

actions = [SemurgDemo.Status, SemurgDemo.Remember, SemurgDemo.Recall, SemurgDemo.Relate, SemurgDemo.Forget, SemurgDemo.Context, SemurgDemo.Document]
need = ~w(memory_status memory_remember memory_recall memory_relate memory_forget memory_context memory_document)

step = fn name, ok, detail ->
  IO.puts("DEMO-STEP #{name} #{if ok, do: "ok", else: "FAIL"} #{inspect(String.slice(SemurgNode.text(detail), 0, 200))}")
  ok
end

# a tool result that says it failed: judged on the node's DECODED reply (Req decodes the JSON body): ok false, a truthy error or a refusal
# field. Never the bare word "refused": memory_status carries refused_at_ms / refused_groups counters on an ok:true reply (r11.125
# false-failed every demo on it). A reply that is not an object keeps the textual ok:false / error:true check. Error tuples are judged by
# `answered` (kind == :error).
truthy? = fn v -> v not in [nil, false, "", 0] end
failed? = fn
  %{} = o -> o["ok"] == false or truthy?.(o["error"]) or truthy?.(o["refused"]) or truthy?.(o["refusal"])
  t ->
    s = t |> SemurgNode.text() |> String.replace(~r/\s+/, "") |> String.downcase()
    s == "" or String.contains?(s, [~s("ok":false), ~s("error":true)])
end

# run an Action through Jido's own executor and flatten the answer to plain text
call = fn action, params ->
  case Jido.Exec.run(action, params) do  # snippet
    {:ok, %{answer: a}} -> {:ok, a}           # the decoded reply, judged as an object by failed?; `answered` flattens it for the text checks
    {:ok, other} -> {:ok, other}
    {:error, reason} -> {:error, SemurgNode.text(reason)}
  end
end

finish = fn ok, detail ->
  IO.puts("DEMO-RESULT #{id} #{if ok, do: "PASS", else: "FAIL"} scope=#{scope} #{detail}")
  System.halt(if ok, do: 0, else: 1)
end

facts = %{entities: [%{name: person, type: "person"}, %{name: org, type: "organisation"}], relations: [%{source: person, target: org, type: "WORKS_AT"}]}  # snippet
project = "Orion #{run_id}"
text = "#{person} works at #{org} and leads the billing rewrite there."
doc_b64 = Base.encode64("Meeting notes\n\n#{person} approved the #{project} budget on Monday.\n")
junk_b64 = Base.encode64(:binary.list_to_bin(Enum.to_list(0..63)))   # not a document: the node must refuse it by name
names = Enum.map(actions, & &1.name())

ok0 = step.("the seven memory Actions are defined", Enum.sort(names) == Enum.sort(need), names)
unless ok0, do: finish.(false, "the seven Actions did not define")

# The same scenario as every framework: all seven memory calls, text sent WITH its facts, a context answer cited to its passage, a
# document, a name never stored, a refusal by name, forget and its proof. Every call is timed (DEMO-TIME <tool> <ms>).
timed = fn action, params ->
  t0 = System.monotonic_time(:microsecond)
  r = call.(action, params)
  IO.puts("DEMO-TIME #{action.name()} #{:erlang.float_to_binary((System.monotonic_time(:microsecond) - t0) / 1000, decimals: 1)}")
  r
end
has = &String.contains?/2
# an answer the node gave (HTTP 2xx) that is not a refusal, and whose text passes pred
answered = fn label, {kind, t}, pred -> s = SemurgNode.text(t); step.(label, kind == :ok and not failed?.(t) and pred.(s), s) end
# G7: the answer QUALITY counts, not only the seven calls: a fact TWO relations out must be an answer.
# Five facts that make a two-relation question, in this run's own scope.
g7_facts = %{
  entities: for({n, ty} <- [{"Priya Raman", "person"}, {"Orion", "project"}, {"Halcyon Labs", "organization"}, {"Vega", "library"}, {"Tomas Berg", "person"}], do: %{name: n, type: ty}),
  relations: for({a, r, b} <- [{"Priya Raman", "LEADS", "Orion"}, {"Orion", "BELONGS_TO", "Halcyon Labs"}, {"Orion", "DEPENDS_ON", "Vega"},
                               {"Tomas Berg", "MAINTAINS", "Vega"}, {"Priya Raman", "MENTORS", "Tomas Berg"}], do: %{source: a, target: b, type: r})
}
# a facts-only remember answers {"ok":true,"mode":"facts","counts":{"relations":N,...}} (no agent_facts: that is the content form)
g7_stored? = fn
  {:ok, %{} = o} -> o["ok"] == true and (get_in(o, ["counts", "relations"]) || 0) >= 5
  _ -> false
end
# the reply's facts include Tomas Berg MAINTAINS Vega and Orion DEPENDS_ON Vega (the chain two relations out)
g7_answered? = fn
  {:ok, %{} = o} ->
    facts = for %{"kind" => "fact"} = i <- List.wrap(o["items"]), do: {i["subject"], i["relation"], i["object"] || i["text"]}   # compact: object; full: text
    {"Tomas Berg", "MAINTAINS", "Vega"} in facts and {"Orion", "DEPENDS_ON", "Vega"} in facts
  _ -> false
end

st = timed.(SemurgDemo.Status, %{})
rm = timed.(SemurgDemo.Remember, %{content: text, facts: facts, source: "agent-demo/#{id}"})
rc = timed.(SemurgDemo.Recall, %{subject: person})
cx = timed.(SemurgDemo.Context, %{query: "Where does #{person} work?"})
rl = timed.(SemurgDemo.Relate, %{from: person, to: mentee, type: "MENTORS"})
rc2 = timed.(SemurgDemo.Recall, %{subject: person})

# the agent path: a Jido agent runs the Action with cmd/2 and the answer lands in its state
{agent, _directives} = SemurgDemo.MemoryAgent.cmd(SemurgDemo.MemoryAgent.new(), {SemurgDemo.Recall, %{subject: person}})  # snippet
agent_answer = SemurgNode.text(agent.state.answer)

dc = timed.(SemurgDemo.Document, %{content_base64: doc_b64, name: "notes-#{run_id}.txt"})
dx = timed.(SemurgDemo.Context, %{query: "What did #{person} approve?"})
g7r = timed.(SemurgDemo.Remember, %{facts: g7_facts, source: "agent-demo/#{id}/g7"})
g7 = timed.(SemurgDemo.Context, %{query: "Who maintains the library that Priya's project depends on?", k: 8, hops: 2})
ms = timed.(SemurgDemo.Recall, %{subject: "Nobody #{run_id}"})
rf = timed.(SemurgDemo.Document, %{content_base64: junk_b64, name: "junk.bin"})
fg = timed.(SemurgDemo.Forget, %{subject: person, reason: "agent-demo/#{id} cleanup"})
gn = timed.(SemurgDemo.Recall, %{subject: person})

rt = %{
  status: answered.("memory_status", st, fn _ -> true end),
  remember: answered.("memory_remember (text + two entities + a WORKS_AT relation)", rm, &has.(&1, "agent_facts")),
  recall: answered.("memory_recall(#{inspect(person)}) names #{inspect(org)}", rc, &has.(&1, org)),
  context: answered.("memory_context returns the passage with its citation", cx, &(has.(&1, "billing rewrite") and has.(&1, "citation"))),
  relate: answered.("memory_relate(#{inspect(person)} MENTORS #{inspect(mentee)})", rl, &(&1 != "")),
  recall2: answered.("memory_recall again names the new edge #{inspect(mentee)}", rc2, &has.(&1, mentee)),
  document: answered.("memory_document stores a text file", dc, &has.(&1, "doc_id")),
  docctx: answered.("memory_context finds the document's passage (#{inspect(project)})", dx, &has.(&1, project)),
  g7remember: step.("memory_remember (G7: five entities, five relations)", g7_stored?.(g7r), SemurgNode.text(elem(g7r, 1))),
  g7: step.("G7: a two-relation question names Tomas Berg MAINTAINS Vega and Orion DEPENDS_ON Vega", g7_answered?.(g7) and not failed?.(elem(g7, 1)), SemurgNode.text(elem(g7, 1))),
  miss: answered.("a name never stored answers nothing_stored", ms, &has.(&1, "nothing_stored")),
  refusal: step.("a file that is not a document is refused by name", elem(rf, 0) == :error and has.(elem(rf, 1), "document_unsupported_kind"), elem(rf, 1)),
  forget: answered.("memory_forget(#{inspect(person)})", fg, &(&1 != "")),
  gone: answered.("after forget, memory_recall(#{inspect(person)}) answers nothing_stored", gn, &has.(&1, "nothing_stored"))
}
agent_ok = step.("agent.cmd(memory_recall) puts the answer in the agent's state", has.(agent_answer, org), agent_answer)

# ONE APP, MANY END USERS, in the same scope: what end user A stores, end user B never sees. An Action that dropped user_id would put
# both users in one memory, and B's recall would name A's fact: this step fails on exactly that.
lena = "Lena #{run_id}"
user_a = "user-a-#{run_id}"
ua = call.(SemurgDemo.Remember, %{facts: %{entities: [%{name: lena, type: "person"}, %{name: org, type: "organisation"}], relations: [%{source: lena, target: org, type: "WORKS_AT"}]}, user_id: user_a})
ra = call.(SemurgDemo.Recall, %{subject: lena, user_id: user_a})
rb = call.(SemurgDemo.Recall, %{subject: lena, user_id: "user-b-#{run_id}"})
users_ok =
  Enum.all?([
    answered.("user_id: end user A stores #{inspect(lena)} WORKS_AT #{inspect(org)}", ua, &(&1 != "")),
    answered.("user_id: end user A's recall(#{inspect(lena)}) names #{inspect(org)}", ra, &has.(&1, org)),
    answered.("user_id: end user B's recall(#{inspect(lena)}) answers nothing_stored (two end users never meet)", rb, &(has.(&1, "nothing_stored") and not has.(&1, org)))
  ])

keys = [:status, :remember, :recall, :context, :relate, :recall2, :document, :docctx, :g7remember, :g7, :miss, :refusal, :forget, :gone]
IO.puts("DEMO-ROUNDTRIP " <> Enum.map_join(keys, " ", fn k -> "#{k}=#{if rt[k], do: "ok", else: "FAIL"}" end))
finish.(Enum.all?(keys, &rt[&1]) and agent_ok and users_ok, "")
