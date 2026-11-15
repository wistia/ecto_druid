defmodule WikiExplorer.DruidRepo do
  @moduledoc """
  A read-only Ecto repo backed by Druid. See `config/runtime.exs` for its
  connection settings.
  """
  use Ecto.Repo, otp_app: :wiki_explorer, adapter: Ecto.Adapters.Druid
end
