defmodule FunWithFlags.SimpleStoreTest do
  use ExUnit.Case, async: false
  import FunWithFlags.TestUtils
  import Mock

  alias FunWithFlags.SimpleStore
  alias FunWithFlags.{Flag, Gate}

  setup_all do
    on_exit(__MODULE__, fn() -> clear_redis_test_db() end)
    :ok
  end


  describe "put(flag_name, %Gate{})" do
    setup do
      name = unique_atom()
      gate = %Gate{type: :boolean, enabled: true}
      flag = %Flag{name: name, gates: [gate]}
      {:ok, name: name, gate: gate, flag: flag}
    end

    test "put() can change the value of a flag", %{name: name, gate: gate} do
      assert {:ok, %Flag{name: ^name, gates: []}} = SimpleStore.lookup(name)

      SimpleStore.put(name, gate)
      assert {:ok, %Flag{name: ^name, gates: [^gate]}} = SimpleStore.lookup(name)

      gate2 = %Gate{gate | enabled: false}
      SimpleStore.put(name, gate2)
      assert {:ok, %Flag{name: ^name, gates: [^gate2]}} = SimpleStore.lookup(name)
      refute match? {:ok, %Flag{name: ^name, gates: [^gate]}}, SimpleStore.lookup(name)
    end

    test "put() returns the tuple {:ok, %Flag{}}", %{name: name, gate: gate, flag: flag} do
      assert {:ok, ^flag} = SimpleStore.put(name, gate)
    end
  end


  describe "delete(flag_name, gate)" do
    setup do
      group_gate = %Gate{type: :group, for: :muggles, enabled: false}
      bool_gate = %Gate{type: :boolean, enabled: true}
      name = unique_atom()

      SimpleStore.put(name, bool_gate)
      SimpleStore.put(name, group_gate)
      {:ok, flag} = SimpleStore.lookup(name)
      assert %Flag{name: ^name, gates: [^bool_gate, ^group_gate]} = flag

      {:ok, name: name, bool_gate: bool_gate, group_gate: group_gate}
    end

    test "delete(flag_name, gate) can change the value of a flag", %{name: name, bool_gate: bool_gate, group_gate: group_gate} do
      assert {:ok, %Flag{name: ^name, gates: [^bool_gate, ^group_gate]}} = SimpleStore.lookup(name)

      SimpleStore.delete(name, bool_gate)
      assert {:ok, %Flag{name: ^name, gates: [^group_gate]}} = SimpleStore.lookup(name)
      SimpleStore.delete(name, group_gate)
      assert {:ok, %Flag{name: ^name, gates: []}} = SimpleStore.lookup(name)
    end

    test "delete(flag_name, gate) returns the tuple {:ok, %Flag{}}", %{name: name, bool_gate: bool_gate, group_gate: group_gate} do
      assert {:ok, %Flag{name: ^name, gates: [^group_gate]}} = SimpleStore.delete(name, bool_gate)
    end

    test "deleting is safe and idempotent", %{name: name, bool_gate: bool_gate, group_gate: group_gate} do
      assert {:ok, %Flag{name: ^name, gates: [^group_gate]}} = SimpleStore.delete(name, bool_gate)
      assert {:ok, %Flag{name: ^name, gates: [^group_gate]}} = SimpleStore.delete(name, bool_gate)
      assert {:ok, %Flag{name: ^name, gates: []}} = SimpleStore.delete(name, group_gate)
      assert {:ok, %Flag{name: ^name, gates: []}} = SimpleStore.delete(name, group_gate)
    end
  end


  describe "delete(flag_name)" do
    setup do
      group_gate = %Gate{type: :group, for: :muggles, enabled: false}
      bool_gate = %Gate{type: :boolean, enabled: true}
      name = unique_atom()

      SimpleStore.put(name, bool_gate)
      SimpleStore.put(name, group_gate)
      {:ok, flag} = SimpleStore.lookup(name)
      assert %Flag{name: ^name, gates: [^bool_gate, ^group_gate]} = flag

      {:ok, name: name, bool_gate: bool_gate, group_gate: group_gate}
    end

    test "delete(flag_name) will reset all the flag gates", %{name: name, bool_gate: bool_gate, group_gate: group_gate} do
      assert {:ok, %Flag{name: ^name, gates: [^bool_gate, ^group_gate]}} = SimpleStore.lookup(name)

      SimpleStore.delete(name)
      assert {:ok, %Flag{name: ^name, gates: []}} = SimpleStore.lookup(name)
    end

    test "delete(flag_name, gate) returns the tuple {:ok, %Flag{}}", %{name: name} do
      assert {:ok, %Flag{name: ^name, gates: []}} = SimpleStore.delete(name)
    end

    test "deleting is safe and idempotent", %{name: name} do
      assert {:ok, %Flag{name: ^name, gates: []}} = SimpleStore.delete(name)
      assert {:ok, %Flag{name: ^name, gates: []}} = SimpleStore.delete(name)
    end
  end


  describe "lookup(flag_name)" do
    test "looking up an undefined flag returns an flag with no gates" do
      name = unique_atom()
      assert {:ok, %Flag{name: ^name, gates: []}} = SimpleStore.lookup(name)
    end

    test "looking up a saved flag returns the flag" do
      name = unique_atom()
      gate = %Gate{type: :boolean, enabled: true}

      assert {:ok, %Flag{name: ^name, gates: []}} = SimpleStore.lookup(name)
      SimpleStore.put(name, gate)
      assert {:ok, %Flag{name: ^name, gates: [^gate]}} = SimpleStore.lookup(name)
    end  
  end


  describe "integration: enable and disable with the top-level API" do
    test "looking up a disabled flag" do
      name = unique_atom()
      FunWithFlags.disable(name)
      assert {:ok, %Flag{name: ^name, gates: [%Gate{type: :boolean, enabled: false}]}} = SimpleStore.lookup(name)
    end

    test "looking up an enabled flag" do
      name = unique_atom()
      FunWithFlags.enable(name)
      assert {:ok, %Flag{name: ^name, gates: [%Gate{type: :boolean, enabled: true}]}} = SimpleStore.lookup(name)
    end
  end


  describe "in case of Persistent store failure" do
    alias FunWithFlags.Store.Persistent

    test "it raises an error" do
      name = unique_atom()

      with_mock(Persistent, [], get: fn(^name) -> {:error, "mocked error"} end) do
        assert_raise RuntimeError, "Can't load feature flag", fn() ->
          SimpleStore.lookup(name)
        end
        assert called(Persistent.get(name))
        assert {:error, "mocked error"} = Persistent.get(name)
      end
    end
  end
end
