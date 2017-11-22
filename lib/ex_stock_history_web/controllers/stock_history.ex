defmodule ExStockHistoryWeb.StockHistory do
  use ExStockHistoryWeb, :controller

  def keys_to_atom(map) do
    for {key, val} <- map, into: %{}, do: {String.to_atom(key), val}
  end

  def google_search(query) do
    HTTPoison.get!("https://www.google.fi/search?q=#{URI.encode(query)}").body
    |> Floki.find("h3[class='r']")
    |> Floki.raw_html
    |> String.replace("<h3 class=\"r\">", "")
    |> String.replace("<a href=\"/url?q=", "")
    |> String.trim_trailing("</a></h3>")
    |> String.split("</a></h3>")
    |> Enum.map(&(String.split(&1, "\">")))
    |> Enum.reject(fn(x) -> Enum.count(x) != 2 end)
    |> Enum.map(fn([url, title]) ->
      %{url: url
      |> String.split("&sa=U")
      |> List.first(), title: Floki.text(title)} end)
    |> Enum.reject(fn(x) -> String.starts_with?(x.url, "<a href=") end)
#    |> Enum.map(fn(%{url: url, title: title}) ->
#      %{url: url, title: validate_string(title)} end)
  end

  def index(conn, _params) do
    send_resp(conn, :ok, "hello")
  end

  def get_historical_data(id, start, stop) do
    url =
      "https://finance.yahoo.com/quote/#{id}/history?period1=" <>
      "#{start}&period2=#{stop}&interval=1d&filter=history&frequency=1d"
    case HTTPoison.get(url) do
      {:ok, page} -> 
        case String.contains?(page.body, "isPending") do
          true ->
            page.body
            |> Floki.find("script")
            |> Floki.raw_html()
            |> String.split("\"prices\":")
            |> Enum.at(1)
            |> String.split(",\"isPending")
            |> List.first()
            |> Poison.Parser.parse()
          false -> {:error, nil}
        end
      {_error, _page} ->
        {:error, nil}
    end
  end

  def get_yahoo_pages(search_result) do
    search_result
    |> Enum.map(fn(%{title: title, url: url}) -> url end)
    |> Enum.reject(fn(item) ->
      !String.starts_with?(item, "https://finance.yahoo.com/quote/") end)
  end

  def get_id(query) do
    id =
      "#{query} yahoo finance"
      |> google_search()
      |> get_yahoo_pages()

    case Enum.empty?(id) do
      true  -> nil
      false -> 
        id
        |> List.first()
        |> String.trim_trailing("/")
        |> String.split("/")
        |> Enum.reverse()
        |> List.first()
    end
  end

  def respond(conn, id, start, stop) do
    response =
      case get_historical_data(id, start, stop) do
        {:ok, json} ->
          json
          |> Enum.reject(fn(item) ->
            Map.has_key?(item, "type")
          end)
          |> Enum.map(fn(item) -> 
            item = keys_to_atom(item)
            %{item | :date => Timex.to_date(Timex.from_unix(item.date))}
          end)
          |> Enum.reverse()
          |> Poison.encode()
        {_error, _page} -> {:error, nil}
      end
    case response do
      {:ok, json} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, json)
      {_error, _malformed} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, "{\"error\":\"not found\"}")
    end
  end

  def fetch_stock_history(conn, %{"id" => id, "start" => start, "stop" => stop}) do
    respond(conn, id, start, stop)
  end

  def fetch_stock_history(conn, %{"id" => id, "start" => start}) do
    stop = Timex.now() |> Timex.to_unix
    respond(conn, id, start, stop)
  end

  def fetch_stock_history(conn, %{"id" => id, "year" => year}) do
    start = Timex.parse!("#{year}-01-01T00:00:00.000Z", "{ISO:Extended:Z}")
      |> Timex.to_unix()
    stop = Timex.parse!("#{year}-01-01T00:00:00.000Z", "{ISO:Extended:Z}")
      |> Timex.shift(years: 1)
      |> Timex.to_unix()
    respond(conn, id, start, stop)
  end

  def fetch_stock_history(conn, %{"id" => id, "from" => from}) do
    start = Timex.parse!("#{from}-01-01T00:00:00.000Z", "{ISO:Extended:Z}")
      |> Timex.to_unix()
    stop = Timex.to_unix(Timex.now())
    respond(conn, id, start, stop)
  end

  def fetch_stock_history(conn, %{"id" => id}) do
    start = Timex.now() |> Timex.shift(years: -2) |> Timex.to_unix()
    stop = Timex.now() |> Timex.to_unix()
    respond(conn, id, start, stop)
  end

  def fetch_stock_history(conn, %{"query" => query, "start" => start, "stop" => stop}) do
    id = get_id(query)
    respond(conn, id, start, stop)
  end

  def fetch_stock_history(conn, %{"query" => query, "start" => start}) do
    id = get_id(query)
    stop = Timex.now() |> Timex.to_unix()
    respond(conn, id, start, stop)
  end

  def fetch_stock_history(conn, %{"query" => query, "year" => year}) do
    id = get_id(query)
    start = Timex.parse!("#{year}-01-01T00:00:00.000Z", "{ISO:Extended:Z}")
      |> Timex.to_unix()
    stop = Timex.parse!("#{year}-01-01T00:00:00.000Z", "{ISO:Extended:Z}")
      |> Timex.shift(years: 1)
      |> Timex.to_unix()
    respond(conn, id, start, stop)
  end

  def fetch_stock_history(conn, %{"query" => query, "from" => from}) do
    id = get_id(query)
    start = Timex.parse!("#{from}-01-01T00:00:00.000Z", "{ISO:Extended:Z}")
      |> Timex.to_unix()
    stop = Timex.to_unix(Timex.now())
    respond(conn, id, start, stop)
  end

  def fetch_stock_history(conn, %{"query" => query}) do
    id = get_id(query)
    start = Timex.now() |> Timex.shift(years: -2) |> Timex.to_unix()
    stop = Timex.now() |> Timex.to_unix()
    respond(conn, id, start, stop)
  end

  def search_stock_history(conn, _params) do
  	send_resp(conn, :ok, "hi")
  end
end
