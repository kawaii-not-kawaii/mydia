defmodule Mydia.Config.RuntimeCheckOriginTest do
  use ExUnit.Case, async: true

  # `PHX_CHECK_ORIGIN: false` in a compose file is YAML's boolean, and Compose
  # passes that as an empty string. Splitting it produced an empty allowlist,
  # which rejects every origin including the correct one, and shows up only as
  # LiveView reconnecting forever. Mirrors config/runtime.exs.
  defp check_origin(value, host) do
    case value |> to_string() |> String.trim() do
      "false" ->
        false

      origins ->
        case String.split(origins, ",", trim: true) do
          [] -> ["//#{host}"]
          parsed -> parsed
        end
    end
  end

  test "an empty value falls back to the host rather than denying everything" do
    assert check_origin("", "tower") == ["//tower"]
    assert check_origin(nil, "tower") == ["//tower"]
    assert check_origin("   ", "tower") == ["//tower"]
  end

  test "an explicit false still disables the check" do
    assert check_origin("false", "tower") == false
    assert check_origin(" false ", "tower") == false
  end

  test "a list is still split" do
    assert check_origin("//tower,//100.64.1.5", "tower") == ["//tower", "//100.64.1.5"]
  end

  test "the empty allowlist that caused the bug is never produced" do
    for value <- ["", nil, "   ", ",", " , "] do
      refute check_origin(value, "tower") == [],
             "#{inspect(value)} produced an empty allowlist, which rejects every origin"
    end
  end
end
