defmodule TalesForgeWeb.QaLoginHTML do
  @moduledoc "The page of `TalesForgeWeb.QaLoginController`."

  use TalesForgeWeb, :html

  @doc "The token form."
  @spec new(map()) :: Phoenix.LiveView.Rendered.t()
  def new(assigns) do
    ~H"""
    <main id="qa-login" class="mx-auto max-w-md space-y-4 px-4 py-16">
      <h1 class="text-2xl font-bold">QA sign-in</h1>
      <p>This sign-in is for Gentry, the QA bot. It gives a read-only session on the team pages.</p>
      <p :if={@error} id="qa-login-error" role="alert" class="text-error">{@error}</p>
      <form id="qa-login-form" method="post" action="/team/qa-login" class="space-y-3">
        <input type="hidden" name="_csrf_token" value={@token} />
        <label for="qa-token" class="block font-semibold">Token</label>
        <input
          id="qa-token"
          name="token"
          type="password"
          autocomplete="off"
          required
          class="input input-bordered w-full"
        />
        <button id="qa-login-submit" type="submit" class="btn btn-primary">Sign in</button>
      </form>
    </main>
    """
  end
end
