defmodule ExStockHistory.Application do
  use Application

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec
    limit = %Cachex.Limit{ limit: 100, reclaim: 0.2 }
    # Define workers and child supervisors to be supervised
    children = [
      # Start the endpoint when the application starts
      supervisor(ExStockHistoryWeb.Endpoint, []),
#      supervisor(ConCache, [[], [name: :cache]])
      
      worker(Cachex, [:cache,  [limit: limit]])
      # Start your own worker by calling: ExStockHistory.Worker.start_link(arg1, arg2, arg3)
      # worker(ExStockHistory.Worker, [arg1, arg2, arg3]),
    ]
    IO.inspect children
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExStockHistory.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    ExStockHistoryWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
