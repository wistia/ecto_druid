defmodule WikiExplorer.Wiki.ChannelLanguages do
  @moduledoc """
  The `channel_languages` lookup, mapping an IRC channel such as
  `#en.wikipedia` to the language it's written in.

  `mix druid.lookups.sync` creates it in Druid from
  `priv/druid/lookups/channel_languages.json.eex`, whose `lookup_factory`
  call reads this schema. The values come from the `:lookups` config in
  `config/runtime.exs`.

  Query it like a table, or pass it to `lookup/3`:

      WikiExplorer.DruidRepo.get(WikiExplorer.Wiki.ChannelLanguages, "#fr.wikipedia")
      #=> %WikiExplorer.Wiki.ChannelLanguages{channel: "#fr.wikipedia", language: "French"}
  """
  use Ecto.Druid.Lookup, key: :channel, value: :language, injective: true
end
