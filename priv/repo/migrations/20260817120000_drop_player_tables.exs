defmodule Mydia.Repo.Migrations.DropPlayerTables do
  use Ecto.Migration

  # Mydia is a media manager only: the in-browser player, the Flutter client and
  # the p2p remote-access stack that fed them are gone, and with them the watch
  # state they wrote and the device records they paired against.
  #
  # `drop_if_exists` rather than `drop`, because an instance that never enabled
  # remote access still has the tables (migrations created them unconditionally)
  # while a hand-repaired one may not.
  def up do
    drop_if_exists table(:playback_progress)
    drop_if_exists table(:pairing_claims)
    drop_if_exists table(:remote_devices)
    drop_if_exists table(:remote_access_config)

    # Scrub sprites, their WebVTT index and hover-preview clips were only ever
    # consumed by the player's seek bar and the adult grid's hover effect.
    # SQLite has supported ALTER TABLE DROP COLUMN since 3.35 (2021), so no
    # table rebuild is needed here — unlike a type or nullability change.
    #
    # Plain `remove`, not `remove_if_exists`: ecto_sqlite3 routes the latter
    # through column_change/2, which raises "Not supported by SQLite3". These
    # three columns are created unconditionally by
    # 20251206040615_add_generated_media_fields_to_media_files, so they are
    # always present and the guard buys nothing.
    alter table(:media_files) do
      remove :sprite_blob
      remove :vtt_blob
      remove :preview_blob
    end
  end

  # Irreversible on purpose: the schemas these tables backed no longer exist, so
  # recreating empty tables would buy nothing a fresh migration run doesn't.
  def down do
    raise Ecto.MigrationError, "cannot restore player tables; the schemas were removed"
  end
end
