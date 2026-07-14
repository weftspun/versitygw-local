# versitygw_local

Treat a [Versity](https://github.com/versity/versitygw) S3 gateway as a **local
object-storage host** from Elixir: provision the `versitygw` single binary,
start/stop an embedded gateway serving the S3 API over a posix directory, and get
back an S3 endpoint config for your S3 client.

This library owns the **host lifecycle only** — no bucket/object semantics. Your
application drives S3 (create buckets, put/get objects) with its own client
(e.g. [`:ex_aws_s3`](https://hex.pm/packages/ex_aws_s3)) inside `with_gateway/2`.
Extracted from
[`holographic-item-memory`](https://github.com/weftspun/holographic-item-memory).

## Install

```elixir
def deps do
  [
    {:versitygw_local, github: "weftspun/versitygw_local"}
  ]
end
```

## Use

```elixir
VersitygwLocal.with_gateway([port: 7070, root: "/tmp/s3"], fn s3 ->
  # `s3` is a keyword list for ExAws (:access_key_id, :host, :port, …)
  ExAws.S3.put_bucket("mybucket", "us-east-1") |> ExAws.request(s3)
  ExAws.S3.put_object("mybucket", "k", "v") |> ExAws.request(s3)
end)
```

If nothing is listening on the S3 port, `with_gateway/2` spawns
`versitygw --port :PORT posix <root>` with root credentials, waits for it to
accept connections, runs your function, and tears it down. If a gateway is
already up, it is reused and left running.

### Binary resolution

`VersitygwLocal.bin/1` resolves, in order: an explicit `:bin`, the `VERSITYGW_BIN`
env var (name overridable via `:bin_env`), a bundled `priv/versitygw/` of the OTP
app given as `:priv_app`, then `versitygw` on `$PATH`.

### Provisioning / bundling

`VersitygwLocal.Provision` downloads the pinned `versity/versitygw` single binary
for a `{os, cpu}` target and can install it into a `priv/versitygw/` directory a
release bundles:

```elixir
# in a Burrito/release step, for the target being built:
VersitygwLocal.Provision.install({:linux, :x86_64}, priv_dir)
```

## License

MIT © 2026 K. S. Ernest (iFire) Lee
