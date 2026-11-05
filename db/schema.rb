# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_05_000100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "audit_entries", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "participant_id", null: false
    t.string "action", null: false
    t.jsonb "details", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["event_id"], name: "index_audit_entries_on_event_id"
    t.index ["participant_id"], name: "index_audit_entries_on_participant_id"
  end

  create_table "cells", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "option_id", null: false
    t.integer "position", null: false
    t.string "text", null: false
    t.integer "votes_count", null: false
    t.string "mark", default: "blank", null: false
    t.integer "revision", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "option_id"], name: "index_cells_on_event_id_and_option_id", unique: true
    t.index ["event_id", "position"], name: "index_cells_on_event_id_and_position", unique: true
    t.index ["event_id"], name: "index_cells_on_event_id"
    t.index ["option_id"], name: "index_cells_on_option_id"
    t.check_constraint "\"position\" >= 0 AND \"position\" <= 24", name: "board_positions"
    t.check_constraint "mark::text = ANY (ARRAY['blank'::character varying, 'question'::character varying, 'cross'::character varying]::text[])", name: "valid_cell_mark"
  end

  create_table "draws", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "participant_id", null: false
    t.string "seed", null: false
    t.string "algorithm", null: false
    t.jsonb "snapshot", null: false
    t.string "snapshot_digest", null: false
    t.jsonb "result", null: false
    t.datetime "created_at", null: false
    t.index ["event_id"], name: "index_draws_on_event_id", unique: true
    t.index ["participant_id"], name: "index_draws_on_participant_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "title", null: false
    t.string "slug", null: false
    t.text "description"
    t.datetime "opens_at", null: false
    t.datetime "closes_at", null: false
    t.string "state", default: "collecting", null: false
    t.boolean "rehearsal", default: false, null: false
    t.integer "revision", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_events_on_slug", unique: true
    t.check_constraint "closes_at > opens_at", name: "valid_voting_window"
    t.check_constraint "state::text = ANY (ARRAY['collecting'::character varying, 'live'::character varying, 'archived'::character varying]::text[])", name: "valid_event_state"
  end

  create_table "login_tokens", force: :cascade do |t|
    t.bigint "participant_id", null: false
    t.string "token_digest", null: false
    t.string "interaction_id", null: false
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.index ["interaction_id"], name: "index_login_tokens_on_interaction_id", unique: true
    t.index ["participant_id"], name: "index_login_tokens_on_participant_id"
    t.index ["token_digest"], name: "index_login_tokens_on_token_digest", unique: true
  end

  create_table "options", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "participant_id", null: false
    t.string "text", limit: 100, null: false
    t.string "normalized_text", null: false
    t.datetime "disqualified_at"
    t.string "moderation_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "normalized_text"], name: "index_options_on_event_id_and_normalized_text", unique: true
    t.index ["event_id"], name: "index_options_on_event_id"
    t.index ["id", "event_id"], name: "index_options_on_id_and_event_id", unique: true
    t.index ["participant_id"], name: "index_options_on_participant_id"
  end

  create_table "participants", force: :cascade do |t|
    t.string "discord_id", null: false
    t.string "display_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discord_id"], name: "index_participants_on_discord_id", unique: true
  end

  create_table "proposals", force: :cascade do |t|
    t.bigint "cell_id", null: false
    t.bigint "participant_id", null: false
    t.integer "revision", null: false
    t.string "mark", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cell_id", "participant_id", "revision"], name: "index_proposals_on_cell_id_and_participant_id_and_revision", unique: true
    t.index ["cell_id"], name: "index_proposals_on_cell_id"
    t.index ["participant_id"], name: "index_proposals_on_participant_id"
    t.check_constraint "mark::text = ANY (ARRAY['question'::character varying, 'cross'::character varying]::text[])", name: "valid_proposal_mark"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "participant_id", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["participant_id"], name: "index_sessions_on_participant_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.binary "payload", null: false
    t.datetime "created_at", null: false
    t.bigint "channel_hash", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "votes", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.bigint "participant_id", null: false
    t.bigint "option_id", null: false
    t.integer "slot", null: false
    t.datetime "created_at", null: false
    t.index ["event_id"], name: "index_votes_on_event_id"
    t.index ["option_id"], name: "index_votes_on_option_id"
    t.index ["participant_id", "event_id", "slot"], name: "index_votes_on_participant_id_and_event_id_and_slot", unique: true
    t.index ["participant_id", "option_id"], name: "index_votes_on_participant_id_and_option_id", unique: true
    t.index ["participant_id"], name: "index_votes_on_participant_id"
    t.check_constraint "slot >= 1 AND slot <= 5", name: "five_vote_slots"
  end

  add_foreign_key "audit_entries", "events"
  add_foreign_key "audit_entries", "participants"
  add_foreign_key "cells", "events"
  add_foreign_key "cells", "options"
  add_foreign_key "draws", "events"
  add_foreign_key "draws", "participants"
  add_foreign_key "login_tokens", "participants"
  add_foreign_key "options", "events"
  add_foreign_key "options", "participants"
  add_foreign_key "proposals", "cells"
  add_foreign_key "proposals", "participants"
  add_foreign_key "sessions", "participants"
  add_foreign_key "votes", "events"
  add_foreign_key "votes", "options"
  add_foreign_key "votes", "options", column: ["option_id", "event_id"], primary_key: ["id", "event_id"]
  add_foreign_key "votes", "participants"
end
