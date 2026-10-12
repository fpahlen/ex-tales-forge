defmodule TalesForgeWeb.FlashAutohideTest do
  use TalesForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TalesForgeWeb.CoreComponents
  alias TalesForgeWeb.Layouts

  defp flash_html(assigns) do
    render_component(&CoreComponents.flash/1, assigns)
  end

  describe "flash/1 autohide" do
    test "a toast stays open by default" do
      html = flash_html(%{kind: :info, flash: %{"info" => "Saved."}})

      assert html =~ "Saved."
      refute html =~ "phx-hook"
      refute html =~ "data-autohide-ms"
    end

    test "autohide adds the hook and the 5 second delay" do
      html = flash_html(%{kind: :info, flash: %{"info" => "Saved."}, autohide: true})

      assert html =~ ~s(phx-hook="TalesForgeWeb.CoreComponents.FlashAutohide")
      assert html =~ ~s(data-autohide-ms="5000")
      assert html =~ ~s(role="status")
    end
  end

  describe "flash_group/1" do
    test "an info flash closes itself" do
      html = render_component(&Layouts.flash_group/1, flash: %{"info" => "Saved."})

      info = html |> LazyHTML.from_fragment() |> LazyHTML.query("#flash-info")
      assert LazyHTML.attribute(info, "data-autohide-ms") == ["5000"]
      assert LazyHTML.attribute(info, "role") == ["status"]
    end

    test "an error flash stays open until someone closes it" do
      html = render_component(&Layouts.flash_group/1, flash: %{"error" => "Failed."})

      error = html |> LazyHTML.from_fragment() |> LazyHTML.query("#flash-error")
      assert Enum.count(error) == 1
      assert LazyHTML.attribute(error, "data-autohide-ms") == []
      assert LazyHTML.attribute(error, "phx-hook") == []
      assert LazyHTML.attribute(error, "role") == ["alert"]
    end
  end
end
