defmodule Mydia.SelfSignedCert do
  @moduledoc """
  Manages the self-signed SSL certificate backing the endpoint's HTTPS listener.

  Mydia is normally reached over plain HTTP behind a reverse proxy that
  terminates TLS. This certificate exists for the case where it is not: an
  instance reached directly on `HTTPS_PORT`, where a browser warning is
  preferable to no encryption at all. It is generated once and reused.
  """

  require Logger

  @cert_filename "mydia-self-signed.pem"
  @key_filename "mydia-self-signed-key.pem"

  @doc """
  Ensures a self-signed certificate exists, generating one if necessary.

  Returns `{:ok, cert_path, key_path, fingerprint}` where:
  - `cert_path` is the absolute path to the certificate file
  - `key_path` is the absolute path to the private key file
  - `fingerprint` is the SHA256 fingerprint of the certificate (hex string)

  If the certificate already exists, returns the paths and fingerprint.
  If the certificate doesn't exist, generates a new one.

  ## Configuration

  Reads from Application config `:mydia, :direct_urls`:
  - `:data_dir` - Directory to store certificates (default: "priv/data")

  ## Examples

      iex> SelfSignedCert.ensure_certificate()
      {:ok, "/path/to/cert.pem", "/path/to/key.pem", "A1:B2:C3:..."}

  """
  def ensure_certificate do
    data_dir = get_data_dir()
    cert_path = Path.join(data_dir, @cert_filename)
    key_path = Path.join(data_dir, @key_filename)

    # Ensure data directory exists
    File.mkdir_p!(data_dir)

    if File.exists?(cert_path) and File.exists?(key_path) do
      # Certificate exists, compute fingerprint and return
      fingerprint = compute_fingerprint(cert_path)
      {:ok, cert_path, key_path, fingerprint}
    else
      # Generate new certificate
      generate_certificate(cert_path, key_path)
    end
  end

  @doc """
  Computes the SHA256 fingerprint of a certificate file.

  Returns the fingerprint as a colon-separated hex string (e.g., "A1:B2:C3:...").

  ## Examples

      iex> SelfSignedCert.compute_fingerprint("/path/to/cert.pem")
      "A1:B2:C3:D4:..."

  """
  def compute_fingerprint(cert_path) do
    case File.read(cert_path) do
      {:ok, pem_data} ->
        # Parse PEM to get DER-encoded certificate
        [{:Certificate, der_cert, :not_encrypted}] = :public_key.pem_decode(pem_data)

        # Compute SHA256 hash of the DER-encoded certificate
        hash = :crypto.hash(:sha256, der_cert)

        # Format as colon-separated hex string
        hash
        |> Base.encode16()
        |> String.graphemes()
        |> Enum.chunk_every(2)
        |> Enum.map_join(":", &Enum.join/1)

      {:error, reason} ->
        Logger.error("Failed to read certificate for fingerprint: #{inspect(reason)}")
        nil
    end
  end

  # Private helpers

  defp get_data_dir do
    config = Application.get_env(:mydia, :direct_urls, [])
    Keyword.get(config, :data_dir, "priv/data")
  end

  defp generate_certificate(cert_path, key_path) do
    Logger.info("Generating self-signed certificate for direct access...")

    # Use openssl command to generate certificate and key
    # This is more reliable than trying to build ASN.1 structures manually
    subject = "/C=US/O=Mydia/CN=Mydia Self-Signed"

    # Generate private key and self-signed certificate in one command
    {output, exit_code} =
      System.cmd(
        "openssl",
        [
          "req",
          "-x509",
          "-newkey",
          "rsa:2048",
          "-keyout",
          key_path,
          "-out",
          cert_path,
          "-sha256",
          # 10 years
          "-days",
          "3650",
          # Don't encrypt the private key
          "-nodes",
          "-subj",
          subject
        ],
        stderr_to_stdout: true
      )

    if exit_code != 0 do
      Logger.error("Failed to generate certificate: #{output}")
      {:error, :certificate_generation_failed}
    else
      # Set restrictive permissions on private key
      File.chmod!(key_path, 0o600)

      Logger.info("Self-signed certificate generated successfully")
      Logger.info("Certificate: #{cert_path}")
      Logger.info("Private key: #{key_path}")

      # Compute and return fingerprint
      fingerprint = compute_fingerprint(cert_path)
      {:ok, cert_path, key_path, fingerprint}
    end
  end
end
