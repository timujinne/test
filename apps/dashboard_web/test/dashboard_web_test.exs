defmodule DashboardWebTest do
  use ExUnit.Case, async: true

  describe "DashboardWeb application" do
    test "application module exists" do
      assert Code.ensure_loaded?(DashboardWeb)
    end

    test "endpoint module exists" do
      assert Code.ensure_loaded?(DashboardWeb.Endpoint)
    end

    test "router module exists" do
      assert Code.ensure_loaded?(DashboardWeb.Router)
    end
  end
end
