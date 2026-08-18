defmodule MydiaWeb.SessionController do
  @moduledoc """
  Local authentication controller.

  Provides username/password login when LOCAL_AUTH_ENABLED is true.
  Can be disabled in favor of OIDC-only authentication.
  """
  use MydiaWeb, :controller

  alias Mydia.Accounts
  alias Mydia.Auth.Guardian
  alias Mydia.Config

  @doc """
  Renders the login form.
  """
  def new(conn, _params) do
    # Redirect to first-time setup if no users exist
    # The setup page will offer both local admin creation and OIDC login options
    if Accounts.any_users_exist?() do
      # Check if local auth is enabled
      config = Config.get()

      if config.auth.local_enabled do
        render(conn, :new,
          changeset: Accounts.change_user(%Mydia.Accounts.User{}),
          oidc_configured: oidc_configured?()
        )
      else
        conn
        |> put_flash(:error, "Local authentication is disabled")
        |> redirect(to: "/")
      end
    else
      conn
      |> redirect(to: ~p"/setup")
    end
  end

  # Check if OIDC is configured
  defp oidc_configured? do
    case Application.get_env(:ueberauth, Ueberauth) do
      nil -> false
      config -> Keyword.get(config, :providers, []) != []
    end
  end

  @doc """
  Handles local login with username and password.
  """
  def create(conn, %{"user" => %{"username" => username, "password" => password}}) do
    # Check if local auth is enabled
    config = Config.get()

    if config.auth.local_enabled do
      case Accounts.get_user_by_username(username) do
        nil ->
          conn
          |> put_flash(:error, "Invalid username or password")
          |> render(:new,
            changeset: Accounts.change_user(%Mydia.Accounts.User{}),
            oidc_configured: oidc_configured?()
          )

        user ->
          if Accounts.verify_password(user, password) do
            # Update last login timestamp
            Accounts.update_last_login(user)

            # Sign in the user via Guardian, which stores the token in session
            # under the :guardian_default_token key that VerifySession expects.
            # Also store under :guardian_token for backward compatibility with
            # code that reads that key directly (e.g., logout).
            {:ok, token, _claims} = Guardian.create_token(user)

            conn
            |> Guardian.Plug.sign_in(user)
            |> put_session(:guardian_default_token, token)
            |> put_session(:guardian_token, token)
            |> put_flash(:info, "Successfully logged in!")
            |> redirect(to: "/")
          else
            conn
            |> put_flash(:error, "Invalid username or password")
            |> render(:new,
              changeset: Accounts.change_user(%Mydia.Accounts.User{}),
              oidc_configured: oidc_configured?()
            )
          end
      end
    else
      conn
      |> put_flash(:error, "Local authentication is disabled")
      |> redirect(to: "/")
    end
  end
end
