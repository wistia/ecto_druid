defmodule Ecto.Druid.Query.IP do
  @moduledoc """
  Druid [IP address functions](https://druid.apache.org/docs/latest/querying/sql-scalar#ip-address-functions).
  """
  import Ecto.Druid.Util, only: [sql_function: 1]

  @doc "Returns true if the address belongs to the subnet literal, else false. If address is not a valid IPv4 address, then false is returned. This function is more efficient if address is an integer instead of a string."
  sql_function ipv4_match(address, subnet)

  @doc "Parses address into an IPv4 address stored as an integer . If address is an integer that is a valid IPv4 address, then it is passed through. Returns null if address cannot be represented as an IPv4 address."
  sql_function ipv4_parse(address)

  @doc "Converts address into an IPv4 address dotted-decimal string. If address is a string that is a valid IPv4 address, then it is passed through. Returns null if address cannot be represented as an IPv4 address."
  sql_function ipv4_stringify(address)

  @doc "Returns 1 if the IPv6 address belongs to the subnet literal, else 0. If address is not a valid IPv6 address, then 0 is returned."
  sql_function ipv6_match(address, subnet)
end
