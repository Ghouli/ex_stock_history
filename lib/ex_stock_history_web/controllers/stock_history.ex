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

#  def get_historical_data(%{"id" => id, "start" => start, "stop" => stop}) do
#    url =
#      "https://finance.yahoo.com/quote/#{id}/history?period1=" <>
#      "#{start}&period2=#{stop}&interval=1d&filter=history&frequency=1d"
#    case HTTPoison.get(url) do
#      {:ok, page} -> 
#        case String.contains?(page.body, "isPending") do
#          true ->
#            page.body
#            |> Floki.find("script")
#            |> Floki.raw_html()
#            |> String.split("\"prices\":")
#            |> Enum.at(1)
#            |> String.split(",\"isPending")
#            |> List.first()
#            |> Poison.Parser.parse()
#          false -> {:error, nil}
#        end
#      {_error, _page} ->
#        {:error, nil}
#    end
#  end

  def get_historical_data(%{"id" => id, "start" => start, "stop" => stop}) do
    filename =
      Path.wildcard("/home/ghouli/stock_data/#{id}-*.json")
    #IO.puts "filename: #{filename}"
    data =
      filename
      |> File.read!()
      |> Poison.Parser.parse!()
      |> Enum.reject(fn(item) ->
          start < item["date"] && stop > item["date"]
      end)
    {:ok, data}
  end

  def get_yahoo_pages(search_result) do
    search_result
    |> Enum.map(fn(%{title: title, url: url}) -> url end)
    |> Enum.reject(fn(item) ->
      !String.starts_with?(item, "https://finance.yahoo.com/quote/") end)
  end

  def format_csv(data, query) do
    csv =
      data
      |> Enum.map(fn(item) ->
        "#{item.date},#{item.close},#{item.adjclose}"
      end)
    csv =
      ["date,close,adjclose"] ++ csv
      |> Enum.join("\n")
    id = query["id"]
    from =
      query["start"]
      |> Timex.from_unix()
      |> Timex.to_date()
    to =
      query["stop"]
      |> Timex.from_unix()
      |> Timex.to_date()
    filename = "#{id}_#{from}_#{to}.csv"
    {filename, csv}
  end

  def format_data(data, query) do
    data =
      data
      |> Enum.reject(fn(item) ->
        Map.has_key?(item, "type")
      end)
      |> Enum.map(fn(item) -> 
        item = keys_to_atom(item)
        %{item | :date => Timex.to_date(Timex.from_unix(item.date))}
      end)
    data = case query["order"] == "asc" do
      true  -> Enum.reverse(data)
      false -> data
    end
    data =
      case query["datatype"] == "csv" do
        true  ->
          {filename, csv} = format_csv(data, query)
          %{
            header:
              %{
                key: "content-disposition",
                value: "attachment; filename=\"#{filename}\""
              },
            type: "text/csv",
            data: csv
          }
        false ->
          %{
            header:
              %{
                key: "",
                value: "",
              },
            type: "application/json",
            data: Poison.encode!(data)
          }
      end
    {:ok, data}
  end

  def respond(conn, {:ok, query}) do
    response =
      case get_historical_data(query) do
        {:ok, data} ->
          format_data(data, query)
        {_error, _page} -> {:error, nil}
      end
    case response do
      {:ok, data} ->
        conn
        |> put_resp_header(data.header.key, data.header.value)
        |> put_resp_content_type(data.type)
        |> send_resp(200, data.data)
      {_error, _malformed} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, "{\"error\":\"not found\"}")
    end
  end

  def respond(conn, {:error, message}) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, "{\"error\":\"#{message}\"}")
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

  def get_start(), do: Timex.now() |> Timex.shift(years: -2) |> Timex.to_unix()
  def get_start(from) do
    "#{from}-01-01T00:00:00.000Z"
    |> Timex.parse!("{ISO:Extended:Z}")
    |> Timex.to_unix()
  end

  def get_stop(), do: Timex.now() |> Timex.to_unix()
  def get_stop(to) do
    "#{to}-12-31T23:59:00.000Z"
    |> Timex.parse!("{ISO:Extended:Z}")
    |> Timex.to_unix()
  end

  def build_query(parameters) do
    query =
      %{
        "id" =>
          case Map.has_key?(parameters, "id") do
            true  -> parameters["id"]
            false ->
              case Map.has_key?(parameters, "query") do
                true  -> get_id(parameters["query"])
                false -> nil
              end
          end,
        "start" =>
          cond do
            Map.has_key?(parameters, "year") ->
              get_start(parameters["year"])
            Map.has_key?(parameters, "from") ->
              get_start(parameters["from"])
            Map.has_key?(parameters, "start") ->
              parameters["start"]
            true -> get_start()
          end,
        "stop" =>
          cond do
            Map.has_key?(parameters, "year") ->
              get_stop(parameters["year"])
            Map.has_key?(parameters, "to") ->
              get_stop(parameters["to"])
            Map.has_key?(parameters, "stop") ->
              parameters["stop"]
            true -> get_stop()
          end,
        "order" =>
          case Map.has_key?(parameters, "order") &&
            String.contains?(parameters["order"], "asc") do
              true  -> "asc"
              false -> "desc"
            end,
        "datatype" =>
          cond do
            Map.has_key?(parameters, "datatype") ->
              parameters["datatype"]
            true -> "json"
          end,
      }
    case query["id"] != nil && query["start"] != nil
      && query["stop"] != nil && query["datatype"] != nil do
        true  -> {:ok, query}
        false -> {:error, "invalid or missing parameters"}
      end
  end

  def fetch_stock_history(conn, parameters) do
    IO.inspect parameters
    query = build_query(parameters)
    respond(conn, query)
  end

  def fetch_stock_history(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, "{\"error\":\"missing parameters\"}")
  end

  def search_stock_history(conn, _params) do
  	send_resp(conn, :ok, "hi")
  end
end
