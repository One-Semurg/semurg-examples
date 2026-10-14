# Run: elixir snippet.exs   (SEMURG_API_TOKEN must be set in the environment)
Mix.install([{:jido, "~> 2.0"}, {:jido_action, "~> 2.0"}, {:req, "~> 0.5"}])

defmodule Semurg.Node do
  @base System.get_env("SEMURG_MCP_URL", "http://127.0.0.1:4000/v1/mcp") |> String.replace_suffix("/v1/mcp", "")
  @scope System.get_env("SEMURG_MCP_SCOPE", "default")
  @token System.fetch_env!("SEMURG_API_TOKEN")

  # the HTTP memory routes read the scope from the body
  def post(verb, body) do
    {:ok, %Req.Response{status: 200, body: answer}} =
      Req.post(@base <> "/v1/memory/" <> verb, json: Map.put(body, :scope, @scope), headers: [{"authorization", "Bearer " <> @token}], retry: false)

    {:ok, %{answer: answer}}
  end
end

defmodule Semurg.Remember do
  use Jido.Action, name: "memory_remember", description: "Store facts in shared agent memory", schema: [facts: [type: :map, required: true]]
  @impl true
  def run(params, _context), do: Semurg.Node.post("remember", Map.take(params, [:facts]))
end

defmodule Semurg.Recall do
  use Jido.Action, name: "memory_recall", description: "Recall what is stored about ONE entity", schema: [subject: [type: :string, required: true]]
  @impl true
  def run(params, _context), do: Semurg.Node.post("recall", Map.take(params, [:subject]))
end

facts = %{entities: [%{name: "Ada", type: "person"}, %{name: "Acme", type: "organisation"}], relations: [%{source: "Ada", target: "Acme", type: "WORKS_AT"}]}
{:ok, _} = Jido.Exec.run(Semurg.Remember, %{facts: facts})
IO.inspect(Jido.Exec.run(Semurg.Recall, %{subject: "Ada"}), limit: :infinity, printable_limit: :infinity)
