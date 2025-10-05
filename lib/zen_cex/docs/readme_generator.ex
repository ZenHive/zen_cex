defmodule ZenCex.Docs.ReadmeGenerator do
  @moduledoc """
  Generates README.md sections from example module documentation.

  This module extracts @moduledoc and @doc attributes from example modules
  and converts them to markdown format for README generation.

  ## Design

  - Single source of truth: Example modules contain all documentation
  - Auto-sync: README is generated from actual working code
  - Tested examples: All code examples have corresponding tests
  - Template-based: Use EEx for flexible README structure

  ## Usage

      # Extract all example module docs
      sections = ZenCex.Docs.ReadmeGenerator.extract_all_sections()

      # Generate markdown for specific module
      markdown = ZenCex.Docs.ReadmeGenerator.module_to_markdown(ZenCex.Examples.BinanceQuickStart)
  """

  @example_modules [
    ZenCex.Examples.BinanceQuickStart,
    ZenCex.Examples.CredentialManagement,
    ZenCex.Examples.BinanceSpotTrading,
    ZenCex.Examples.BinanceFuturesTrading,
    ZenCex.Examples.BinanceMarketData,
    ZenCex.Examples.BinanceWebsocketStreams,
    ZenCex.Examples.BybitTrading,
    ZenCex.Examples.BinanceStrategies,
    ZenCex.Examples.ProductionRestFeatures,
    ZenCex.Examples.DebugTroubleshooting,
    ZenCex.Examples.EndpointDiscovery
  ]

  @doc """
  Extract documentation sections from all example modules.

  Returns a list of section maps with module name, title, content.

  ## Returns

  ```elixir
  [
    %{
      module: ZenCex.Examples.BinanceQuickStart,
      title: "Quick Start",
      moduledoc: "Quick start examples...",
      functions: [
        %{name: :check_connectivity, doc: "...", examples: ["..."]}
      ]
    },
    ...
  ]
  ```
  """
  @spec extract_all_sections() :: [map()]
  def extract_all_sections do
    Enum.map(@example_modules, fn module ->
      %{
        module: module,
        title: module_to_title(module),
        moduledoc: get_moduledoc(module),
        functions: extract_function_docs(module)
      }
    end)
  end

  @doc """
  Convert example module to markdown section.

  Generates a complete markdown section including:
  - Section header (H2)
  - Module description
  - Function examples with code blocks

  ## Examples

      markdown = ZenCex.Docs.ReadmeGenerator.module_to_markdown(
        ZenCex.Examples.BinanceQuickStart
      )
  """
  @spec module_to_markdown(module()) :: String.t()
  def module_to_markdown(module) do
    title = module_to_title(module)
    moduledoc = get_moduledoc(module)
    functions = extract_function_docs(module)

    # Build markdown
    Enum.join(["## #{title}\n", format_moduledoc(moduledoc), "\n", format_functions(functions)], "\n")
  end

  @doc """
  Generate usage-rules.md content from template.

  Uses the usage-rules.md.eex template to generate AI editor documentation.
  The template includes static sections for critical warnings and patterns.

  ## Returns

  Complete usage-rules.md content as string.
  """
  @spec generate_usage_rules() :: String.t()
  def generate_usage_rules do
    template_path = Path.join([File.cwd!(), "priv", "templates", "usage-rules.md.eex"])

    if !File.exists?(template_path) do
      raise "Template file not found: #{template_path}"
    end

    template_content = File.read!(template_path)

    # No assigns needed - template is self-contained
    EEx.eval_string(template_content, assigns: [])
  end

  @doc """
  Get @moduledoc content from a module.

  Returns the raw moduledoc string, or empty string if not defined.
  """
  @spec get_moduledoc(module()) :: String.t()
  def get_moduledoc(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} when is_binary(moduledoc) ->
        moduledoc

      {:docs_v1, _, _, _, :none, _, _} ->
        ""

      _ ->
        ""
    end
  end

  @doc """
  Extract all function documentation from a module.

  Returns list of maps with function name, doc, and examples.
  """
  @spec extract_function_docs(module()) :: [map()]
  def extract_function_docs(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, function_docs} ->
        function_docs
        |> Enum.filter(fn
          {{:function, _name, _arity}, _, _, _, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {{:function, name, arity}, _, _, doc, _} ->
          %{
            name: name,
            arity: arity,
            doc: extract_doc_string(doc),
            examples: extract_examples(doc)
          }
        end)
        |> Enum.reject(&(&1.doc == ""))

      _ ->
        []
    end
  end

  # Private Functions

  defp module_to_title(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp extract_doc_string(%{"en" => doc}) when is_binary(doc), do: doc
  defp extract_doc_string(:none), do: ""
  defp extract_doc_string(_), do: ""

  defp extract_examples(%{"en" => doc}) when is_binary(doc) do
    # Extract code blocks from markdown
    # Look for ## Examples section
    case Regex.run(~r/## Examples\s+(.*)/s, doc) do
      [_, examples_section] ->
        # First try to extract explicit code blocks
        code_blocks =
          ~r/```elixir\n(.*?)```/s
          |> Regex.scan(examples_section)
          |> Enum.map(fn [_, code] -> String.trim(code) end)

        # If no code blocks, extract doctest-style examples (iex> format)
        if code_blocks == [] do
          extract_doctest_examples(examples_section)
        else
          code_blocks
        end

      nil ->
        []
    end
  end

  defp extract_examples(_), do: []

  defp extract_doctest_examples(text) do
    # Extract iex> examples and convert to clean code
    lines = String.split(text, "\n")

    lines
    |> Enum.chunk_by(fn line -> String.starts_with?(String.trim(line), "iex>") end)
    |> Enum.filter(fn chunk ->
      chunk != [] and String.starts_with?(String.trim(hd(chunk)), "iex>")
    end)
    |> Enum.map(fn chunk ->
      chunk
      |> Enum.map_join("\n", fn line ->
        line
        |> String.trim()
        |> String.replace_prefix("iex> ", "")
        |> String.replace_prefix("...> ", "")
      end)
      |> String.trim()
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp format_moduledoc(moduledoc) do
    # Extract just the description part (before ## sections)
    case String.split(moduledoc, ~r/\n## /, parts: 2) do
      [description | _] -> String.trim(description)
      [] -> ""
    end
  end

  defp format_functions(functions) do
    Enum.map_join(functions, "\n\n", fn func ->
      [
        "### #{format_function_name(func.name)}",
        "",
        format_function_doc(func.doc),
        "",
        format_function_examples(func.examples)
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    end)
  end

  defp format_function_name(name) do
    name
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_function_doc(doc) do
    # Extract first paragraph (before ## sections)
    case String.split(doc, ~r/\n## /, parts: 2) do
      [description | _] -> String.trim(description)
      [] -> ""
    end
  end

  defp format_function_examples([]), do: ""

  defp format_function_examples(examples) do
    Enum.map_join(examples, "\n\n", fn example ->
      String.trim("""
      ```elixir
      #{example}
      ```
      """)
    end)
  end
end
