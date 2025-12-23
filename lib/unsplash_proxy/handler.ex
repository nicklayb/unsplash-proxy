defmodule UnsplashProxy.Handler do
  alias UnsplashProxy.Cache
  require Logger

  def init(_), do: []

  @unsplash_host URI.parse("https://api.unsplash.com")

  def call(%Plug.Conn{} = conn, _opts) do
    method = to_atom_method(conn.method)

    path =
      case conn.path_info do
        [] -> ""
        parts -> Path.join(parts)
      end

    uri = %URI{@unsplash_host | path: path, query: conn.query_string}

    with {:ok, response} <- request(method, uri) do
      respond_from_response(conn, uri, response)
    end
  end

  defp request(method, uri) do
    Cache.cached(cache_key(uri), [cache_match: &should_cache?/1], fn ->
      Logger.info("[#{inspect(__MODULE__)}.Req] [#{method}] [#{uri.path}] [#{uri.query}]")

      Req.request(method: method, url: uri, headers: headers(), raw: true)
    end)
  end

  defp should_cache?({:ok, %Req.Response{status: status}}) do
    status in 200..299
  end

  defp should_cache?(_) do
    false
  end

  defp cache_key(%URI{path: path, query: query}) do
    :sha256
    |> :crypto.hash("#{path}?#{query}")
    |> Base.encode16()
    |> String.downcase()
  end

  defp respond_from_response(conn, %URI{} = uri, %Req.Response{} = response) do
    Logger.debug(
      "[#{inspect(__MODULE__)}.Req] [#{response.status}] [#{uri.path}] [#{inspect(response.headers)}]"
    )

    response.headers
    |> Enum.reduce(conn, fn {key, value}, acc ->
      Plug.Conn.put_resp_header(acc, key, Enum.join(value, ";"))
    end)
    |> Plug.Conn.send_resp(response.status, response.body)
  end

  defp headers do
    api_key = unsplash_api_key()

    [
      {"Authorization", "Client-ID #{api_key}"},
      {"Accept-Version", "v1"}
    ]
  end

  defp unsplash_api_key do
    :unsplash_proxy
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:unsplash_api_key)
  end

  defp to_atom_method(method) do
    method
    |> String.downcase()
    |> String.to_existing_atom()
  end
end
