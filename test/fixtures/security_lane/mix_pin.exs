defmodule Example.MixProject do
  use Mix.Project

  def project, do: [app: :example, version: "0.1.0", deps: deps()]

  defp deps do
    [
      {:decimal, "~> 3.2"},
      {:plug, "~> 1.18"}
    ]
  end
end
