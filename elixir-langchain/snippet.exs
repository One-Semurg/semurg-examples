# Run: elixir snippet.exs   (SEMURG_API_TOKEN must be set in the environment)
Mix.install([{:langchain, "~> 0.4"}, {:langchain_mcp, "~> 0.2"}, {:plug, "~> 1.0"}])   # langchain_mcp compiles a test server that needs Plug.Router

Logger.configure(level: :warning)   # the MCP client logs every request at debug level

url = URI.parse(System.get_env("SEMURG_MCP_URL", "http://127.0.0.1:4000/v1/mcp"))
headers = %{
  "Authorization" => "Bearer " <> System.fetch_env!("SEMURG_API_TOKEN"),
  "X-Semurg-Scope" => System.get_env("SEMURG_MCP_SCOPE", "default")
}
facts = %{
  "entities" => [%{"name" => "Ada", "type" => "person"}, %{"name" => "Acme", "type" => "organisation"}],
  "relations" => [%{"source" => "Ada", "target" => "Acme", "type" => "WORKS_AT"}]
}

defmodule Semurg.MCP do
  use LangChain.MCP.Client, name: "semurg", version: "1.0.0", protocol_version: "2025-03-26"
end

{:ok, _} = Semurg.MCP.start_link(transport: {:streamable_http, base_url: "#{url.scheme}://#{url.host}:#{url.port}", mcp_path: url.path, headers: headers})
adapter = LangChain.MCP.Adapter.new(client: Semurg.MCP)

# the client does its MCP handshake in the background: ask until the memory tools are listed
wait = fn wait, tries ->
  tools = LangChain.MCP.Adapter.to_functions(adapter)
  cond do
    length(tools) >= 6 -> tools
    tries == 0 -> raise "the node listed no memory tools"
    true -> Process.sleep(500); wait.(wait, tries - 1)
  end
end

by_name = wait.(wait, 60) |> Map.new(&{&1.name, &1})
by_name["memory_remember"].function.(%{"facts" => facts}, %{})
IO.inspect(by_name["memory_recall"].function.(%{"subject" => "Ada"}, %{}), limit: :infinity, printable_limit: :infinity)
System.halt(0)
