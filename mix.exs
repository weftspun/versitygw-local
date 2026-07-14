# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule VersitygwLocal.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/weftspun/versitygw_local"

  def project do
    [
      app: :versitygw_local,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Treat a Versity S3 gateway as a local object-storage host: provision the " <>
          "versitygw single binary, start/stop an embedded gateway over a posix " <>
          "directory, and hand back an S3 endpoint config. Extracted from " <>
          "holographic-item-memory.",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => @source_url}
      ],
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  # No runtime deps: the gateway is an external binary; S3 config is a plain
  # keyword list the caller feeds to its own S3 client (e.g. :ex_aws_s3).
  defp deps, do: []
end
