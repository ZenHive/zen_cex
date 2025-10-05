defmodule Mix.Tasks.ZenCex.GenerateReadme do
  @shortdoc "Generate README.md from example module documentation"

  @moduledoc """
  Generates README.md and usage-rules.md from example module documentation.

  This task extracts documentation from all example modules and generates
  documentation files using EEx templates. This ensures documentation
  stays in sync with actual working code examples.

  ## Usage

      # Preview generated README (outputs to stdout)
      mix zen_cex.generate_readme

      # Write to README.md
      mix zen_cex.generate_readme --write

      # Generate usage-rules.md for AI editors
      mix zen_cex.generate_readme --usage-rules

      # Generate both README and usage-rules
      mix zen_cex.generate_readme --all

      # Write to custom file
      mix zen_cex.generate_readme --output custom_readme.md

  ## Options

    * `--write` - Write output to README.md
    * `--usage-rules` - Generate usage-rules.md for AI editors
    * `--all` - Generate both README.md and usage-rules.md
    * `--output PATH` - Write output to specified file
    * `--preview` - Preview first 50 lines (default when no options)

  ## Examples

      # Preview README output
      mix zen_cex.generate_readme

      # Update README.md
      mix zen_cex.generate_readme --write

      # Update usage-rules.md
      mix zen_cex.generate_readme --usage-rules

      # Update both
      mix zen_cex.generate_readme --all

      # Create separate file
      mix zen_cex.generate_readme --output GENERATED_README.md
  """

  use Mix.Task

  alias ZenCex.Docs.ReadmeGenerator

  @default_output_path "README.md"
  @usage_rules_path "usage-rules.md"
  @readme_template_path "priv/templates/README.md.eex"

  @impl Mix.Task
  def run(args) do
    # Parse arguments
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [write: :boolean, usage_rules: :boolean, all: :boolean, output: :string, preview: :boolean],
        aliases: [w: :write, u: :usage_rules, a: :all, o: :output, p: :preview]
      )

    # Start the application to ensure modules are loaded
    Mix.Task.run("app.start")

    # Handle output based on options
    cond do
      opts[:all] ->
        generate_both()

      opts[:usage_rules] ->
        generate_usage_rules()

      opts[:output] ->
        generate_readme_to_file(opts[:output])

      opts[:write] ->
        generate_readme_to_file(@default_output_path)

      true ->
        preview_readme()
    end
  end

  # Private Functions

  defp generate_both do
    Mix.shell().info("Generating both README.md and usage-rules.md...")
    generate_readme_to_file(@default_output_path)
    generate_usage_rules()
  end

  defp generate_readme_to_file(path) do
    # Extract documentation from all example modules
    Mix.shell().info("Extracting documentation from example modules...")
    sections = ReadmeGenerator.extract_all_sections()

    # Prepare template data
    assigns = prepare_assigns(sections)

    # Generate README content
    Mix.shell().info("Generating README content...")
    content = render_readme_template(assigns)

    write_to_file(content, path)
  end

  defp preview_readme do
    Mix.shell().info("Extracting documentation from example modules...")
    sections = ReadmeGenerator.extract_all_sections()

    assigns = prepare_assigns(sections)

    Mix.shell().info("Generating README content...")
    content = render_readme_template(assigns)

    preview_output(content, "README.md")
  end

  defp generate_usage_rules do
    Mix.shell().info("Generating usage-rules.md for AI editors...")
    content = ReadmeGenerator.generate_usage_rules()

    write_to_file(content, @usage_rules_path)
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

  defp render_readme_template(assigns) do
    template_path = Path.join(File.cwd!(), @readme_template_path)

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

  defp preview_output(content, filename) do
    lines = String.split(content, "\n")
    preview_lines = Enum.take(lines, 50)
    total_lines = length(lines)

    Mix.shell().info("\n" <> String.duplicate("=", 80))
    Mix.shell().info("PREVIEW of #{filename} (first 50 of #{total_lines} lines):")
    Mix.shell().info(String.duplicate("=", 80) <> "\n")

    Enum.each(preview_lines, &Mix.shell().info/1)

    Mix.shell().info("\n" <> String.duplicate("=", 80))
    Mix.shell().info("Showing #{length(preview_lines)} of #{total_lines} lines")
    Mix.shell().info(String.duplicate("=", 80))

    Mix.shell().info("\nTo write to #{filename}, run:")

    if filename == "README.md" do
      Mix.shell().info("  mix zen_cex.generate_readme --write")
    else
      Mix.shell().info("  mix zen_cex.generate_readme --usage-rules")
    end

    Mix.shell().info("\nTo generate both files, run:")
    Mix.shell().info("  mix zen_cex.generate_readme --all")
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} bytes"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
end
