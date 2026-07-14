# versitygw_local

Treat a [Versity](https://github.com/versity/versitygw) S3 gateway as a local
object-storage host from Elixir: provision the `versitygw` single binary,
start/stop an embedded gateway serving the S3 API over a posix directory, and get
back an S3 endpoint config for your S3 client.
