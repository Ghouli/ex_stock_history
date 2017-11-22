defmodule ExStockHistoryWeb.Router do
  use ExStockHistoryWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ExStockHistoryWeb do
    pipe_through :browser # Use the default browser stack

    get "/", PageController, :index
  end

  scope "/stocks", ExStockHistoryWeb do
    pipe_through :api
    get "/api/history", StockHistory, :fetch_stock_history
    post "/api/history", StockHistory, :search_stock_history
  end

  # Other scopes may use custom stacks.
  # scope "/api", ExStockHistoryWeb do
  #   pipe_through :api
  # end
end
