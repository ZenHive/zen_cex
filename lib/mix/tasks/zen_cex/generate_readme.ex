defmodule Mix.Tasks.ZenCex.GenerateReadme do
  @shortdoc "Generate README.md from example module documentation"

  @moduledoc """
  Generates README.md from example module documentation.

  This task extracts documentation from all example modules and generates
  a complete README.md using the EEx template. This ensures the README
  stays in sync with actual working code examples.

  ## Usage

      # Preview generated README (outputs to stdout)
      mix zen_cex.generate_readme

      # Write to README.md
      mix zen_cex.generate_readme --write

      # Write to custom file
      mix zen_cex.generate_readme --output custom_readme.md

  ## Options

    * `--write` - Write output to README.md
    * `--output PATH` - Write output to specified file
    * `--preview` - Preview first 50 lines (default when no options)

  ## Examples

      # Preview output
      mix zen_cex.generate_readme

      # Update README.md
      mix zen_cex.generate_readme --write

      # Create separate file
      mix zen_cex.generate_readme --output GENERATED_README.md
  """

  use Mix.Task

  alias ZenCex.Docs.ReadmeGenerator

  @default_output_path "README.md"
  @template_path "priv/templates/README.md.eex"

  @impl Mix.Task
  def run(args) do
    # Parse arguments
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [write: :boolean, output: :string, preview: :boolean],
        aliases: [w: :write, o: :output, p: :preview]
      )

    # Start the application to ensure modules are loaded
    Mix.Task.run("app.start")

    # Extract documentation from all example modules
    Mix.shell().info("Extracting documentation from example modules...")
    sections = ReadmeGenerator.extract_all_sections()

    # Prepare template data
    assigns = prepare_assigns(sections)

    # Generate README content
    Mix.shell().info("Generating README content...")
    content = render_template(assigns)

    # Handle output based on options
    cond do
      opts[:output] ->
        write_to_file(content, opts[:output])

      opts[:write] ->
        write_to_file(content, @default_output_path)

      true ->
        preview_output(content)
    end
  end

  # Private Functions

  defp prepare_assigns(sections) do
    formatted_sections =
      Enum.map(sections, fn section ->
        %{
          title: section.title,
          moduledoc_summary: extract_summary(section.moduledoc),
          functions: format_functions_for_template(section.functions)
        }
      end)

    [sections: formatted_sections]
  end

  defp extract_summary(moduledoc) do
    # Extract first paragraph or up to first ## heading
    case String.split(moduledoc, ~r/\n\n|\n## /, parts: 2) do
      [summary | _] -> String.trim(summary)
      [] -> ""
    end
  end

  defp format_functions_for_template(functions) do
    Enum.map(functions, fn func ->
      %{
        title: format_function_title(func.name, func.arity),
        doc_summary: extract_summary(func.doc),
        examples: func.examples
      }
    end)
  end

  defp format_function_title(name, arity) do
    name_str =
      name
      |> Atom.to_string()
      |> String.split("_")
      |> Enum.map_join(" ", &String.capitalize/1)

    "#{name_str}/#{arity}"
  end

  defp render_template(assigns) do
    template_path = Path.join(File.cwd!(), @template_path)

    if !File.exists?(template_path) do
      Mix.raise("Template file not found: #{template_path}")
    end

    template_content = File.read!(template_path)

    EEx.eval_string(template_content, assigns: assigns)
  end

  defp write_to_file(content, path) do
    file_path = Path.join(File.cwd!(), path)

    Mix.shell().info("Writing to #{path}...")
    File.write!(file_path, content)

    lines = content |> String.split("\n") |> length()
    bytes = byte_size(content)

    Mix.shell().info([
      :green,
      "✓ Successfully generated #{path}",
      :reset,
      " (#{lines} lines, #{format_bytes(bytes)})"
    ])
  end

  defp preview_output(content) do
    lines = String.split(content, "\n")
    preview_lines = Enum.take(lines, 50)
    total_lines = length(lines)

    Mix.shell().info("\n" <> String.duplicate("=", 80))
    Mix.shell().info("PREVIEW (first 50 of #{total_lines} lines):")
    Mix.shell().info(String.duplicate("=", 80) <> "\n")

    Enum.each(preview_lines, &Mix.shell().info/1)

    Mix.shell().info("\n" <> String.duplicate("=", 80))
    Mix.shell().info("Showing #{length(preview_lines)} of #{total_lines} lines")
    Mix.shell().info(String.duplicate("=", 80))

    Mix.shell().info("\nTo write to README.md, run:")
    Mix.shell().info("  mix zen_cex.generate_readme --write")
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} bytes"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
end
