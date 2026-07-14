# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule VersitygwLocal.Provision do
  @moduledoc """
  Provision the single `versitygw` binary for a build target.

  Downloads the matching [`versity/versitygw`](https://github.com/versity/versitygw)
  single-binary release, extracts the executable, and installs it into a
  `priv/versitygw/` directory a release can bundle. Pure Erlang/`curl` — no
  external archive tools required (`:zip` / `:erl_tar`).

  Downloads are cached under `~/.cache/versitygw_local/`.

  A `target` is `{os, cpu}` where `os ∈ :linux | :darwin | :windows` and
  `cpu ∈ :x86_64 | :aarch64` — the shape a Burrito build step passes.
  """

  require Logger

  @tag "v1.6.0"

  @assets %{
    {:linux, :x86_64} => "versitygw_#{@tag}_Linux_x86_64.tar.gz",
    {:darwin, :aarch64} => "versitygw_#{@tag}_Darwin_arm64.tar.gz",
    {:windows, :x86_64} => "versitygw_#{@tag}_Windows_x86_64.zip"
  }

  @doc """
  Download URL for a `{os, cpu}` target, or `{:error, :unsupported_target}`.
  """
  @spec asset_url({atom(), atom()}) :: {:ok, String.t()} | {:error, :unsupported_target}
  def asset_url(target) do
    case Map.fetch(@assets, target) do
      {:ok, asset} ->
        {:ok, "https://github.com/versity/versitygw/releases/download/#{@tag}/#{asset}"}

      :error ->
        {:error, :unsupported_target}
    end
  end

  @doc """
  Fetch and install the versitygw executable into `priv_dir/versitygw/`, chmod
  0755, returning `{:ok, installed_path}`. Use from a release/Burrito step.
  """
  @spec install({atom(), atom()}, String.t()) :: {:ok, String.t()} | {:error, term()}
  def install(target, priv_dir) do
    with {:ok, bin} <- fetch(target) do
      exe = Path.basename(bin)
      dest_dir = Path.join(priv_dir, "versitygw")
      File.mkdir_p!(dest_dir)
      dest = Path.join(dest_dir, exe)
      File.cp!(bin, dest)
      File.chmod!(dest, 0o755)
      Logger.info("versitygw_local: installed #{exe} -> #{dest}")
      {:ok, dest}
    end
  end

  # --- download + extract ----------------------------------------------------

  defp fetch(target) do
    with {:ok, url} <- asset_url(target) do
      exe = if elem(target, 0) == :windows, do: "versitygw.exe", else: "versitygw"

      try do
        {:ok, fetch_tool(url, exe)}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end
  end

  defp fetch_tool(url, exe) do
    asset = Path.basename(url)
    cache = Path.join([System.user_home!(), ".cache", "versitygw_local", asset])
    extracted = Path.join(Path.dirname(cache), "#{asset}.extracted")
    File.mkdir_p!(Path.dirname(cache))

    unless File.exists?(cache) do
      Logger.info("versitygw_local: downloading #{url}")
      {_, 0} = System.cmd("curl", ["-fsSL", "--retry", "3", "-o", cache, url])
    end

    unless File.dir?(extracted) do
      tmp = extracted <> ".tmp"
      File.rm_rf!(tmp)
      File.mkdir_p!(tmp)

      # Erlang built-ins only — GNU tar can't read .zip; keep it portable.
      if String.ends_with?(asset, ".zip") do
        {:ok, _} = :zip.extract(String.to_charlist(cache), cwd: String.to_charlist(tmp))
      else
        :ok =
          :erl_tar.extract(String.to_charlist(cache), [
            :compressed,
            {:cwd, String.to_charlist(tmp)}
          ])
      end

      File.rename!(tmp, extracted)
    end

    case Path.wildcard(Path.join(extracted, "**/#{exe}")) do
      [bin | _] -> bin
      [] -> raise "no #{exe} inside #{asset}"
    end
  end
end
