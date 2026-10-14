# Customer-side demo: Semurg's seven memory tools as Jido Actions, run by a Jido agent. Part of the fenced examples directory
# (scripts/ci/agent_examples_fence.sh): never imported, built or shipped by the product. No LLM is in the loop: the Actions are run
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

  def status, do: handle(Req.get(base() <> "/v1/memory/status", headers: headers(), retry: false))

  def post(call, body),
    do: handle(Req.post(base() <> "/v1/memory/" <> call, json: Map.put(body, :scope, System.get_env("SEMURG_MCP_SCOPE") || "demo-jido"), headers: headers(), retry: false))   # the HTTP routes read the scope from the BODY (the X-Semurg-Scope header is the MCP door's connection default)

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
  use Jido.Action, name: "memory_status", description: "Report whether shared memory is on for this node and which of YOUR scopes hold facts", schema: []
  @impl true
  def run(_params, _context), do: SemurgNode.status()
end

defmodule SemurgDemo.Remember do
  use Jido.Action, name: "memory_remember", description: "Store facts in shared agent memory", schema: [facts: [type: :map, required: true], content: [type: :string], source: [type: :string]]  # snippet
  @impl true
  def run(params, _context), do: SemurgNode.post("remember", Map.take(params, [:facts, :content, :source]))
end

defmodule SemurgDemo.Recall do
  use Jido.Action, name: "memory_recall", description: "Recall what is stored about ONE entity", schema: [subject: [type: :string, required: true], k: [type: :integer]]
  @impl true
  def run(params, _context), do: SemurgNode.post("recall", Map.take(params, [:subject, :k]))
end

defmodule SemurgDemo.Relate do
  use Jido.Action, name: "memory_relate", description: "Add ONE typed edge between two entities in a scope", schema: [from: [type: :string, required: true], to: [type: :string, required: true], type: [type: :string, required: true]]
  @impl true
  def run(params, _context), do: SemurgNode.post("relate", Map.take(params, [:from, :to, :type]))
end

defmodule SemurgDemo.Forget do
  use Jido.Action, name: "memory_forget", description: "Mark an entity as superseded in a scope", schema: [subject: [type: :string, required: true], reason: [type: :string]]
  @impl true
  def run(params, _context), do: SemurgNode.post("forget", Map.take(params, [:subject, :reason]))
end

defmodule SemurgDemo.Context do
  use Jido.Action, name: "memory_context", description: "Retrieve what the memory holds that is relevant to a question", schema: [query: [type: :string, required: true], hops: [type: :integer], k: [type: :integer]]
  @impl true
  def run(params, _context), do: SemurgNode.post("context", Map.take(params, [:query, :hops, :k]))
end

defmodule SemurgDemo.Document do
  use Jido.Action, name: "memory_document", description: "Store a document (a PDF, a Word .docx, an HTML page or a UTF-8 text file) as memory", schema: [content_base64: [type: :string, required: true], name: [type: :string]]
  @impl true
  def run(params, _context), do: SemurgNode.post("document", Map.take(params, [:content_base64, :name]))
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

# a tool result that says it failed: an error tuple, an ok:false body or a refusal
failed? = fn t ->
  s = t |> SemurgNode.text() |> String.replace(~r/\s+/, "") |> String.downcase()
  s == "" or String.contains?(s, ["refused", ~s("ok"=>false), ~s("error"=>true)])
end

# run an Action through Jido's own executor and flatten the answer to plain text
call = fn action, params ->
  case Jido.Exec.run(action, params) do  # snippet
    {:ok, %{answer: a}} -> {:ok, SemurgNode.text(a)}
    {:ok, other} -> {:ok, SemurgNode.text(other)}
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
answered = fn label, {kind, t}, pred -> step.(label, kind == :ok and not failed?.(t) and pred.(t), t) end

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
  miss: answered.("a name never stored answers nothing_stored", ms, &has.(&1, "nothing_stored")),
  refusal: step.("a file that is not a document is refused by name", elem(rf, 0) == :error and has.(elem(rf, 1), "document_unsupported_kind"), elem(rf, 1)),
  forget: answered.("memory_forget(#{inspect(person)})", fg, &(&1 != "")),
  gone: answered.("after forget, memory_recall(#{inspect(person)}) answers nothing_stored", gn, &has.(&1, "nothing_stored"))
}
agent_ok = step.("agent.cmd(memory_recall) puts the answer in the agent's state", has.(agent_answer, org), agent_answer)

keys = [:status, :remember, :recall, :context, :relate, :recall2, :document, :docctx, :miss, :refusal, :forget, :gone]
IO.puts("DEMO-ROUNDTRIP " <> Enum.map_join(keys, " ", fn k -> "#{k}=#{if rt[k], do: "ok", else: "FAIL"}" end))
finish.(Enum.all?(keys, &rt[&1]) and agent_ok, "")
