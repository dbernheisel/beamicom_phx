defmodule BeamicomPhxWeb.PageController do
  use BeamicomPhxWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
