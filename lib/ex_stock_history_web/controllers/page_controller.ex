defmodule ExStockHistoryWeb.PageController do
  use ExStockHistoryWeb, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
