# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule VersitygwLocal do
  @moduledoc """
  Treat a [Versity](https://github.com/versity/versitygw) S3 gateway as a
  **local object-storage host**.

  This library owns the *host lifecycle* only — provisioning the single
  `versitygw` binary, starting/stopping an embedded gateway serving the S3 API
  over a plain posix directory, and returning an S3 endpoint config. It holds
  **no bucket/object semantics**: the caller drives S3 with its own client
  (e.g. [`:ex_aws_s3`](https://hex.pm/packages/ex_aws_s3)) inside `with_gateway/2`.

  Extracted from `holographic-item-memory`, whose `Holo.Adapters.VersityBlobStore`
  keeps its aria-storage chunking + blob manifests and delegates the host
  lifecycle here.

  ## Example

      VersitygwLocal.with_gateway([port: 7070, root: "/tmp/s3"], fn s3 ->
        # `s3` is a keyword list for ExAws (:access_key_id, :host, :port, …)
        ExAws.S3.put_bucket("mybucket", "us-east-1") |> ExAws.request(s3)
      end)

  ## Binary resolution (`bin/1`)

  In order: an explicit `:bin`, the `VERSITYGW_BIN` env var (name overridable via
  `:bin_env`), a bundled `priv/versitygw/` of the OTP app given as `:priv_app`,
  then `versitygw` on `$PATH`. Provision one with `VersitygwLocal.Provision`.
  """

  require Logger

  @default_port 7070
  @default_access_key "versity"
  @default_secret_key "versity-secret"
  @default_region "us-east-1"
  @ready_timeout_ms 30_000
  @poll_interval_ms 250

  @type opts :: keyword()

  @doc """
  Posix root directory the gateway serves: `opts[:root]`, else `VERSITYGW_ROOT`,
  else `~/.versitygw_local`.
  """
  @spec default_root(opts()) :: String.t()
  def default_root(opts \\ []) do
    opts[:root] || System.get_env("VERSITYGW_ROOT") ||
      Path.join(System.user_home!(), ".versitygw_local")
  end

  @doc """
  Run `fun.(s3_config)` against the gateway, starting (and stopping) an embedded
  versitygw when nothing is already listening on the S3 port. `s3_config` is a
  keyword list suitable for `ExAws.request/2`. Returns `fun`'s result, or
  `{:error, reason}`.

  ## Options
    * `:port` — S3 port (default #{@default_port}).
    * `:root` — posix directory served (see `default_root/1`).
    * `:access_key` / `:secret_key` — gateway root credentials.
    * `:region` — S3 region (default `#{@default_region}`).
    * `:bin` / `:bin_env` / `:priv_app` — binary resolution (see `bin/1`).
  """
  @spec with_gateway(opts(), (keyword() -> result)) :: result | {:error, term()}
        when result: var
  def with_gateway(opts \\ [], fun) do
    port = opts[:port] || @default_port

    {erl_port, os_pid} =
      if listening?(port), do: {nil, nil}, else: spawn_gateway(opts, port)

    try do
      case await_ready(port, @ready_timeout_ms) do
        :ok ->
          fun.(s3_config(opts))

        {:error, reason} ->
          {:error, "S3 gateway did not become ready: #{inspect(reason)}"}
      end
    after
      stop_gateway(erl_port, os_pid)
    end
  end

  @doc """
  S3 endpoint config (keyword list for `ExAws.request/2`) pointing at the local
  gateway. Uses the same `:port` / `:access_key` / `:secret_key` / `:region`
  options as `with_gateway/2`.
  """
  @spec s3_config(opts()) :: keyword()
  def s3_config(opts \\ []) do
    [
      access_key_id: opts[:access_key] || @default_access_key,
      secret_access_key: opts[:secret_key] || @default_secret_key,
      scheme: "http://",
      host: "localhost",
      port: opts[:port] || @default_port,
      region: opts[:region] || @default_region
    ]
  end

  @doc """
  Resolve the versitygw binary: explicit `:bin`, then the `:bin_env` env var
  (default `VERSITYGW_BIN`), then `priv/versitygw/` of `:priv_app`, then `$PATH`.
  """
  @spec bin(opts()) :: {:ok, String.t()} | {:error, String.t()}
  def bin(opts \\ []) do
    exe = if match?({:win32, _}, :os.type()), do: "versitygw.exe", else: "versitygw"
    env_name = opts[:bin_env] || "VERSITYGW_BIN"

    bundled =
      case opts[:priv_app] do
        nil ->
          nil

        app ->
          case :code.priv_dir(app) do
            {:error, _} -> nil
            priv -> Path.join([to_string(priv), "versitygw", exe])
          end
      end

    cond do
      (b = opts[:bin]) && File.exists?(b) -> {:ok, b}
      b = System.get_env(env_name) -> {:ok, b}
      bundled && File.exists?(bundled) -> {:ok, bundled}
      b = System.find_executable("versitygw") -> {:ok, b}
      true -> {:error, "no versitygw binary: set #{env_name}, bundle priv/versitygw, or add to PATH"}
    end
  end

  # --- gateway lifecycle -----------------------------------------------------

  defp spawn_gateway(opts, port) do
    case bin(opts) do
      {:ok, exe} ->
        root = default_root(opts)
        File.mkdir_p!(root)
        Logger.debug("versitygw_local: starting embedded versitygw on port #{port}")

        access = opts[:access_key] || @default_access_key
        secret = opts[:secret_key] || @default_secret_key

        erl_port =
          Port.open({:spawn_executable, exe}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: ["--port", ":#{port}", "posix", root],
            env: [
              {~c"ROOT_ACCESS_KEY", String.to_charlist(access)},
              {~c"ROOT_SECRET_KEY", String.to_charlist(secret)}
            ]
          ])

        os_pid =
          case Port.info(erl_port, :os_pid) do
            {:os_pid, pid} -> pid
            _ -> nil
          end

        {erl_port, os_pid}

      {:error, reason} ->
        raise reason
    end
  end

  defp stop_gateway(nil, _), do: :ok

  defp stop_gateway(erl_port, os_pid) do
    if os_pid do
      case :os.type() do
        {:win32, _} -> System.cmd("taskkill", ["/PID", to_string(os_pid), "/T", "/F"])
        _ -> System.cmd("kill", [to_string(os_pid)])
      end
    end

    if is_port(erl_port) and Port.info(erl_port) != nil, do: Port.close(erl_port)
    :ok
  catch
    _, _ -> :ok
  end

  defp listening?(port) do
    case :gen_tcp.connect(~c"localhost", port, [:binary, active: false], 500) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        true

      {:error, _} ->
        false
    end
  end

  defp await_ready(port, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await(port, deadline)
  end

  defp do_await(port, deadline) do
    cond do
      listening?(port) ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        {:error, :timeout}

      true ->
        Process.sleep(@poll_interval_ms)
        do_await(port, deadline)
    end
  end
end
