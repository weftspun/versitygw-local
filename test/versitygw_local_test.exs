# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule VersitygwLocalTest do
  use ExUnit.Case, async: true

  describe "default_root/1" do
    test "prefers an explicit :root" do
      assert VersitygwLocal.default_root(root: "/tmp/x") == "/tmp/x"
    end

    test "falls back to a home-relative default" do
      assert String.ends_with?(VersitygwLocal.default_root([]), ".versitygw_local")
    end
  end

  describe "s3_config/1" do
    test "builds an ExAws-shaped endpoint config with defaults" do
      cfg = VersitygwLocal.s3_config([])
      assert cfg[:scheme] == "http://"
      assert cfg[:host] == "localhost"
      assert cfg[:port] == 7070
      assert cfg[:region] == "us-east-1"
      assert is_binary(cfg[:access_key_id])
    end

    test "honors overrides" do
      cfg = VersitygwLocal.s3_config(port: 9000, access_key: "ak", secret_key: "sk", region: "eu")
      assert cfg[:port] == 9000
      assert cfg[:access_key_id] == "ak"
      assert cfg[:secret_access_key] == "sk"
      assert cfg[:region] == "eu"
    end
  end

  describe "bin/1" do
    test "prefers an explicit existing :bin" do
      assert {:ok, path} = VersitygwLocal.bin(bin: System.find_executable("sh"))
      assert String.ends_with?(path, "sh")
    end
  end

  describe "Provision" do
    test "asset_url/1 maps supported targets to release URLs" do
      assert {:ok, url} = VersitygwLocal.Provision.asset_url({:linux, :x86_64})
      assert url =~ "versity/versitygw/releases/download/"
      assert url =~ "Linux_x86_64.tar.gz"
    end

    test "asset_url/1 rejects unsupported targets" do
      assert {:error, :unsupported_target} = VersitygwLocal.Provision.asset_url({:plan9, :sparc})
    end

    test "targets/0 lists the three supported triplets" do
      assert {:linux, :x86_64} in VersitygwLocal.Provision.targets()
      assert {:darwin, :aarch64} in VersitygwLocal.Provision.targets()
      assert {:windows, :x86_64} in VersitygwLocal.Provision.targets()
    end
  end
end
