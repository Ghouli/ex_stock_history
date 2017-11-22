defmodule ExStockHistoryWeb.StockHistory do
  use ExStockHistoryWeb, :controller

  def keys_to_atom(map) do
    for {key, val} <- map, into: %{}, do: {String.to_atom(key), val}
  end

  def index(conn, _params) do
    send_resp(conn, :ok, "hello")
  end

  def get_historical_data(id, start, stop) do
    url = "https://finance.yahoo.com/quote/#{id}/history?period1=#{start}&period2=#{stop}&interval=1d&filter=history&frequency=1d"
    data = HTTPoison.get!(url).body
      |> Floki.find("script")
      |> Floki.raw_html()
      |> String.split("\"prices\":")
      |> Enum.at(1)
      |> String.split(",\"isPending")
      |> List.first()
      |> Poison.Parser.parse!()
  end

  def respond(conn, id, start, stop) do
    json = id
      |> get_historical_data(start, stop)
      |> Enum.reject(fn(item) ->
        Map.has_key?(item, "type")
      end)
      |> Enum.map(fn(item) -> 
        item = keys_to_atom(item)
        %{item | :date => Timex.to_date(Timex.from_unix(item.date))}
      end)
      |> Enum.reverse()
      |> Poison.encode!()
    send_resp(conn, :ok, json)
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
    stop = Timex.now()
      |> Timex.to_unix()
    respond(conn, id, start, stop)
  end

  def fetch_stock_history(conn, %{"id" => id}) do
    start = Timex.now() |> Timex.shift(years: -2) |> Timex.to_unix()
    stop = Timex.now() |> Timex.to_unix()
    respond(conn, id, start, stop)
  end


  def search_stock_history(conn, _params) do
  	send_resp(conn, :ok, "hi")
  end
end
