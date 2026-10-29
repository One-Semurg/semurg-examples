# Customer-side demo: calls a Semurg node's MCP memory server through Elixir LangChain's own MCP adapter (the langchain_mcp package, on the Anubis MCP client).
# No LLM is in the loop:
# the tools are called directly through the adapter's LangChain.Function structs, so what this proves is the framework's MCP client against Semurg.
#   SEMURG_MCP_URL=https://NODE/v1/mcp SEMURG_API_TOKEN=... elixir demo.exs        (token optional on an open node)
#   DEMO_INSTALL_ONLY=1 elixir demo.exs      installs the packages and prints their versions, then stops (the runner's phase 1: no token, no url)
# Prints DEMO-VERSION / DEMO-STEP lines and one DEMO-ROUNDTRIP + DEMO-RESULT line; exit 0 PASS, 1 FAIL. A crash prints no result line: the runner reads it as COULD-NOT-JUDGE.
Mix.install([{:langchain, "~> 0.4"}, {:langchain_mcp, "~> 0.2"}, {:plug, "~> 1.0"}])   # langchain_mcp compiles a test server that needs Plug.Router

defmodule Demo do
  @id "elixir-langchain"
  @need ~w(memory_status memory_remember memory_recall memory_relate memory_forget memory_context memory_document)

  def versions do
    for app <- [:langchain, :langchain_mcp, :anubis_mcp, :plug] do
      IO.puts("DEMO-VERSION #{app} #{Application.spec(app, :vsn) || "not-installed"}")
    end
  end

  def step(name, ok, detail \\ "") do
    IO.puts("DEMO-STEP #{name} #{if ok, do: "ok", else: "FAIL"} #{inspect(String.slice(to_string(detail), 0, 200))}")
    ok
  end

  # Flatten whatever the framework hands back (a string, content parts, a map with "text", {:ok, _} / {:error, _}) to plain text; an error is marked.
  def text({:ok, x}), do: text(x)
  def text({:error, x}), do: "[isError] " <> text(x)
  def text(x) when is_binary(x), do: x
  def text(x) when is_list(x), do: Enum.map_join(x, "\n", &text/1)
  def text(%{content: c}), do: text(c)
  def text(%{"text" => t}), do: t
  def text(other), do: inspect(other)

  # The reply as a map when it is a JSON object, else nil.
  def parsed(t) do
    case JSON.decode(t) do
      {:ok, %{} = o} -> o
      _ -> nil
    end
  end

  # A tool result that says it failed: the error mark, or a PARSED top-level object with ok false, a truthy error or a refusal field.
  # Never the bare word "refused": memory_status carries refused_at_ms / refused_groups counters on an ok:true reply (r11.125 false-failed
  # every demo on it). Text that is not an object keeps the textual ok:false / error:true check.
  def failed?(t) do
    cond do
      t == "" or String.starts_with?(t, "[isError]") -> true
      o = parsed(t) -> o["ok"] == false or truthy?(o["error"]) or truthy?(o["refused"]) or truthy?(o["refusal"])
      true -> s = t |> String.replace(" ", "") |> String.downcase(); String.contains?(s, "\"ok\":false") or String.contains?(s, "\"error\":true")
    end
  end

  defp truthy?(v), do: v not in [nil, false, "", 0]

  # G7: a facts-only remember answers {"ok":true,"mode":"facts","counts":{"relations":N,...}} (no agent_facts: that is the content form).
  def g7_stored?(t) do
    case parsed(t) do
      nil -> String.contains?(String.replace(t, " ", ""), "\"relations\":5")
      o -> o["ok"] == true and (get_in(o, ["counts", "relations"]) || 0) >= 5
    end
  end

  # G7: the reply's facts include Tomas Berg MAINTAINS Vega and Orion DEPENDS_ON Vega (the chain two relations out).
  def g7_answered?(t) do
    items = (parsed(t) || %{}) |> Map.get("items") |> List.wrap()
    facts = for %{"kind" => "fact"} = i <- items, do: {i["subject"], i["relation"], i["object"] || i["text"]}   # compact: object; full: text

    if facts != [],
      do: {"Tomas Berg", "MAINTAINS", "Vega"} in facts and {"Orion", "DEPENDS_ON", "Vega"} in facts,
      else: Enum.all?(["MAINTAINS", "DEPENDS_ON", "Tomas Berg", "Vega"], &String.contains?(t, &1))
  end

  # G7: the answer QUALITY counts, not only the seven calls: a fact TWO relations out must be an answer.
  # Five facts that make a two-relation question, in this run's own scope.
  def g7_facts do
    ents = [{"Priya Raman", "person"}, {"Orion", "project"}, {"Halcyon Labs", "organization"}, {"Vega", "library"}, {"Tomas Berg", "person"}]
    rels = [{"Priya Raman", "LEADS", "Orion"}, {"Orion", "BELONGS_TO", "Halcyon Labs"}, {"Orion", "DEPENDS_ON", "Vega"}, {"Tomas Berg", "MAINTAINS", "Vega"},
            {"Priya Raman", "MENTORS", "Tomas Berg"}]
    %{"entities" => for({n, ty} <- ents, do: %{"name" => n, "type" => ty}), "relations" => for({a, r, b} <- rels, do: %{"source" => a, "target" => b, "type" => r})}
  end

  def g7_q, do: "Who maintains the library that Priya's project depends on?"

  # The same scenario for every framework: all seven memory tools, text sent WITH its facts, a context answer cited to its passage, a
  # document, a name never stored, a refusal by name, forget and its proof. Every call is timed (DEMO-TIME <tool> <ms>).
  # `call` is (tool name, args map) -> text.
  @keys [:status, :remember, :recall, :context, :relate, :recall2, :document, :docctx, :g7remember, :g7, :miss, :refusal, :forget, :gone]
  def scenario(call, tool_names, run) do
    person = "Ada #{run}"
    org = "Acme #{run}"
    mentee = "Bea #{run}"
    project = "Orion #{run}"
    text = "#{person} works at #{org} and leads the billing rewrite there."
    doc_b64 = Base.encode64("Meeting notes\n\n#{person} approved the #{project} budget on Monday.\n")
    junk_b64 = Base.encode64(:binary.list_to_bin(Enum.to_list(0..63)))   # not a document: the node must refuse it by name
    facts = %{"entities" => [%{"name" => person, "type" => "person"}, %{"name" => org, "type" => "organisation"}],
              "relations" => [%{"source" => person, "target" => org, "type" => "WORKS_AT"}]}

    timed = fn name, args ->
      t0 = System.monotonic_time(:microsecond)
      # a framework that raises on an MCP error result: keep its text, the step judges it
      out = try do call.(name, args) rescue e -> "[isError] " <> Exception.message(e) end
      IO.puts("DEMO-TIME #{name} #{:erlang.float_to_binary((System.monotonic_time(:microsecond) - t0) / 1000, decimals: 1)}")
      out
    end
    has = &String.contains?/2

    ok? = step("tools/list has the seven memory tools", MapSet.subset?(MapSet.new(@need), MapSet.new(tool_names)), Enum.sort(tool_names) |> inspect())

    rt =
      if ok? do
        st = timed.("memory_status", %{})
        rm = timed.("memory_remember", %{"content" => text, "facts" => facts, "source" => "agent-demo/#{@id}"})
        rc = timed.("memory_recall", %{"subject" => person})
        cx = timed.("memory_context", %{"query" => "Where does #{person} work?"})
        rl = timed.("memory_relate", %{"from" => person, "to" => mentee, "type" => "MENTORS"})
        rc2 = timed.("memory_recall", %{"subject" => person})
        dc = timed.("memory_document", %{"content_base64" => doc_b64, "name" => "notes-#{run}.txt"})
        dx = timed.("memory_context", %{"query" => "What did #{person} approve?"})
        g7r = timed.("memory_remember", %{"facts" => g7_facts(), "source" => "agent-demo/#{@id}/g7"})
        g7 = timed.("memory_context", %{"query" => g7_q(), "k" => 8, "hops" => 2})
        ms = timed.("memory_recall", %{"subject" => "Nobody #{run}"})
        rf = timed.("memory_document", %{"content_base64" => junk_b64, "name" => "junk.bin"})
        fg = timed.("memory_forget", %{"subject" => person, "reason" => "agent-demo/#{@id} cleanup"})
        gn = timed.("memory_recall", %{"subject" => person})
        %{
          status: step("memory_status", not failed?(st), st),
          remember: step("memory_remember (text + two entities + a WORKS_AT relation)", has.(rm, "agent_facts") and not failed?(rm), rm),
          recall: step("memory_recall(#{inspect(person)}) names #{inspect(org)}", has.(rc, org) and not failed?(rc), rc),
          context: step("memory_context returns the passage with its citation", has.(cx, "billing rewrite") and has.(cx, "citation") and not failed?(cx), cx),
          relate: step("memory_relate(#{inspect(person)} MENTORS #{inspect(mentee)})", rl != "" and not failed?(rl), rl),
          recall2: step("memory_recall again names the new edge #{inspect(mentee)}", has.(rc2, mentee) and not failed?(rc2), rc2),
          document: step("memory_document stores a text file", has.(dc, "doc_id") and not failed?(dc), dc),
          docctx: step("memory_context finds the document's passage (#{inspect(project)})", has.(dx, project) and not failed?(dx), dx),
          g7remember: step("memory_remember (G7: five entities, five relations)", g7_stored?(g7r) and not failed?(g7r), g7r),
          g7: step("G7: a two-relation question names Tomas Berg MAINTAINS Vega and Orion DEPENDS_ON Vega", g7_answered?(g7) and not failed?(g7), g7),
          miss: step("a name never stored answers nothing_stored", has.(ms, "nothing_stored") and not failed?(ms), ms),
          refusal: step("a file that is not a document is refused by name", failed?(rf) and has.(rf, "document_unsupported_kind"), rf),
          forget: step("memory_forget(#{inspect(person)})", fg != "" and not failed?(fg), fg),
          gone: step("after forget, memory_recall(#{inspect(person)}) answers nothing_stored", has.(gn, "nothing_stored") and not failed?(gn), gn)
        }
      else
        %{}
      end

    IO.puts("DEMO-ROUNDTRIP " <> Enum.map_join(@keys, " ", fn k -> "#{k}=#{if Map.get(rt, k), do: "ok", else: "FAIL"}" end))
    Enum.all?(@keys, &Map.get(rt, &1))
  end

  def finish(ok, scope, detail \\ "") do
    IO.puts("DEMO-RESULT #{@id} #{if ok, do: "PASS", else: "FAIL"} scope=#{scope} #{detail}")
    System.halt(if ok, do: 0, else: 1)
  end

  # Discover the tools; the client does its MCP handshake in the background, so ask until the tool list is there (or give up after 30 s).
  def discover(adapter, deadline \\ System.monotonic_time(:millisecond) + 30_000) do
    tools = LangChain.MCP.Adapter.to_functions(adapter)
    cond do
      length(tools) >= length(@need) -> tools
      System.monotonic_time(:millisecond) > deadline -> tools
      true -> Process.sleep(500); discover(adapter, deadline)
    end
  end
end

Demo.versions()
if System.get_env("DEMO_INSTALL_ONLY") == "1", do: System.halt(0)

url = URI.parse(System.fetch_env!("SEMURG_MCP_URL"))
token = System.get_env("SEMURG_API_TOKEN", "")
run = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
scope = System.get_env("SEMURG_MCP_SCOPE") || "demo-elixir-langchain-#{run}"
headers = %{"X-Semurg-Scope" => scope}                                    # the node's default scope for this connection
headers = if token == "", do: headers, else: Map.put(headers, "Authorization", "Bearer #{token}")
base = "#{url.scheme}://#{url.host}:#{url.port}"

alias LangChain.MCP.Adapter                                                # snippet
defmodule Semurg.MCP do use LangChain.MCP.Client, name: "semurg", version: "1.0.0", protocol_version: "2025-03-26" end  # snippet
{:ok, _} = Semurg.MCP.start_link(transport: {:streamable_http, base_url: base, mcp_path: url.path, headers: headers})  # snippet
tools = Adapter.new(client: Semurg.MCP) |> Demo.discover()                  # snippet
by_name = Map.new(tools, &{&1.name, &1})

call = fn name, args -> by_name[name].function.(args, %{}) |> Demo.text() end
Demo.finish(Demo.scenario(call, Map.keys(by_name), run), scope)
