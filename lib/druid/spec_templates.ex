defmodule Druid.SpecTemplates do
  @moduledoc false
  # Shared plumbing for the template directories managed by Druid.Supervisors,
  # Druid.Retention, Druid.Lookups and Druid.Tasks: config lookup, template discovery,
  # rendering to decoded JSON, and request options.

  alias Druid.Supervisors.Template

  @repo_keys [:host, :port, :scheme, :auth, :redirect_trusted]
  @connection_keys @repo_keys ++
                     [:plug, :adapter, :finch, :receive_timeout] ++
                     [:retry, :max_retries, :retry_delay, :retry_log_level]

  @doc "Reads `key` from the repo's config, with `opts` taking precedence."
  def config(repo, key, opts) do
    repo.config()
    |> Keyword.get(key, [])
    |> Keyword.merge(opts)
  end

  @doc """
  Returns the templates directory. A relative `:path` is resolved against the
  repo's OTP app directory.
  """
  def root!(repo, config, default_path, error, kind) do
    path = Keyword.get(config, :path, default_path)

    root =
      case Path.type(path) do
        :absolute -> path
        _ -> Application.app_dir(Keyword.fetch!(repo.config(), :otp_app), path)
      end

    unless File.dir?(root) do
      raise error, "#{kind} templates directory not found: #{root}"
    end

    root
  end

  @doc """
  Finds the templates under `root`, skipping partials. Returns
  `{name, path}` pairs sorted by name, where the name is the path relative to
  `root` without its extension.
  """
  def discover(root) do
    root
    |> Path.join("**/*.{json,json.eex}")
    |> Path.wildcard()
    |> Enum.reject(&String.starts_with?(Path.basename(&1), "_"))
    |> Enum.sort()
    |> Enum.map(&{&1 |> Path.relative_to(root) |> strip_ext(), &1})
  end

  @doc "Keeps only the templates named in `only`, raising on unknown names."
  def filter_only(templates, nil, _error, _kind), do: templates

  def filter_only(templates, only, error, kind) do
    only = List.wrap(only)
    names = MapSet.new(templates, fn {name, _path} -> name end)

    case Enum.reject(only, &MapSet.member?(names, &1)) do
      [] -> Enum.filter(templates, fn {name, _path} -> name in only end)
      missing -> raise error, "no #{kind} templates named: #{Enum.join(missing, ", ")}"
    end
  end

  @doc """
  Renders a template with the configured assigns and decodes the result as
  JSON.
  """
  def render!(name, path, root, config, error) do
    assigns =
      config
      |> Keyword.get(:assigns, %{})
      |> to_map()
      |> deep_merge(config |> Keyword.get(:specs, %{}) |> Map.get(name, %{}) |> to_map())
      |> Map.put(:spec_name, name)

    rendered =
      try do
        Template.render_file(path, assigns, root)
      rescue
        e in Template.Error ->
          raise error, "failed to render #{name}: #{Exception.message(e)}"
      end

    case Jason.decode(rendered) do
      {:ok, decoded} ->
        decoded

      # The rendered spec isn't shown, since assigns often hold credentials
      {:error, e} ->
        {line, column} = line_column(rendered, e.position)

        raise error,
              "#{name} rendered invalid JSON at line #{line}, column #{column}: " <>
                Exception.message(e)
    end
  end

  defp line_column(rendered, position) do
    before = binary_part(rendered, 0, min(position, byte_size(rendered)))
    lines = String.split(before, "\n")
    {length(lines), String.length(List.last(lines)) + 1}
  end

  @doc """
  Raises if two items share a key. `name_fun` labels each item in the
  message.
  """
  def check_unique!(items, key_fun, name_fun, error, message) do
    items
    |> Enum.group_by(key_fun)
    |> Enum.filter(fn {_key, items} -> length(items) > 1 end)
    |> Enum.sort()
    |> case do
      [] ->
        items

      dupes ->
        details =
          Enum.map_join(dupes, "; ", fn {key, items} ->
            "#{key} (#{Enum.map_join(items, ", ", name_fun)})"
          end)

        raise error, "#{message}: #{details}"
    end
  end

  @doc """
  Builds `Druid.Client.request!/2` options: the repo's connection settings,
  overridden by the ones in `config`.

  Requests go through the repo's Finch pool while the repo is running. Mix
  tasks and release scripts call these without starting the repo, so they
  fall back to Req's default pool.
  """
  def request_opts(repo, config) do
    repo_config = repo.config()
    finch = Ecto.Adapters.Druid.finch_name(repo, repo_config)

    repo_config
    |> Keyword.take(@repo_keys)
    |> then(&if Process.whereis(finch), do: Keyword.put(&1, :finch, finch), else: &1)
    |> Keyword.merge(Keyword.take(config, @connection_keys))
    |> Keyword.put(:telemetry_metadata, %{repo: repo})
  end

  defp strip_ext(path) do
    path |> String.replace_suffix(".eex", "") |> String.replace_suffix(".json", "")
  end

  @doc "Turns a keyword list of assigns into a map."
  def to_map(value) when is_map(value), do: value
  def to_map(value) when is_list(value), do: Map.new(value)

  @doc "Merges `right` into `left`, recursing into nested maps."
  def deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, %{} = l, %{} = r when not is_struct(l) and not is_struct(r) -> deep_merge(l, r)
      _key, _l, r -> r
    end)
  end
end
