class CreateBingo < ActiveRecord::Migration[8.1]
  def change
    create_table :participants do |t|
      t.string :discord_id, null: false
      t.string :display_name, null: false
      t.timestamps
    end
    add_index :participants, :discord_id, unique: true
    create_table :events do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.datetime :opens_at, null: false
      t.datetime :closes_at, null: false
      t.string :state, null: false, default: "collecting"
      t.boolean :rehearsal, null: false, default: false
      t.integer :revision, null: false, default: 0
      t.timestamps
    end
    add_index :events, :slug, unique: true
    add_check_constraint :events, "closes_at > opens_at", name: "valid_voting_window"
    add_check_constraint :events, "state IN ('collecting', 'live', 'archived')", name: "valid_event_state"
    create_table :options do |t|
      t.references :event, null: false, foreign_key: true
      t.references :participant, null: false, foreign_key: true
      t.string :text, null: false, limit: 100
      t.string :normalized_text, null: false
      t.datetime :disqualified_at
      t.string :moderation_reason
      t.timestamps
    end
    add_index :options, [ :event_id, :normalized_text ], unique: true
    add_index :options, [ :id, :event_id ], unique: true
    create_table :votes do |t|
      t.references :event, null: false, foreign_key: true
      t.references :participant, null: false, foreign_key: true
      t.references :option, null: false, foreign_key: true
      t.integer :slot, null: false
      t.datetime :created_at, null: false
    end
    add_index :votes, [ :participant_id, :event_id, :slot ], unique: true
    add_index :votes, [ :participant_id, :option_id ], unique: true
    add_check_constraint :votes, "slot BETWEEN 1 AND 5", name: "five_vote_slots"
    add_foreign_key :votes, :options, column: [ :option_id, :event_id ], primary_key: [ :id, :event_id ]
    create_table :draws do |t|
      t.references :event, null: false, foreign_key: true, index: { unique: true }
      t.references :participant, null: false, foreign_key: true
      t.string :seed, null: false
      t.string :algorithm, null: false
      t.jsonb :snapshot, null: false
      t.string :snapshot_digest, null: false
      t.jsonb :result, null: false
      t.datetime :created_at, null: false
    end
    create_table :cells do |t|
      t.references :event, null: false, foreign_key: true
      t.references :option, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :text, null: false
      t.integer :votes_count, null: false
      t.string :mark, null: false, default: "blank"
      t.integer :revision, null: false, default: 0
      t.timestamps
    end
    add_index :cells, [ :event_id, :position ], unique: true
    add_index :cells, [ :event_id, :option_id ], unique: true
    add_check_constraint :cells, "position BETWEEN 0 AND 24", name: "board_positions"
    add_check_constraint :cells, "mark IN ('blank', 'question', 'cross')", name: "valid_cell_mark"
    create_table :proposals do |t|
      t.references :cell, null: false, foreign_key: true
      t.references :participant, null: false, foreign_key: true
      t.integer :revision, null: false
      t.string :mark, null: false
      t.timestamps
    end
    add_index :proposals, [ :cell_id, :participant_id, :revision ], unique: true
    add_check_constraint :proposals, "mark IN ('question', 'cross')", name: "valid_proposal_mark"
    create_table :audit_entries do |t|
      t.references :event, null: false, foreign_key: true
      t.references :participant, null: false, foreign_key: true
      t.string :action, null: false
      t.jsonb :details, null: false, default: {}
      t.datetime :created_at, null: false
    end
    create_table :login_tokens do |t|
      t.references :participant, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :interaction_id, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.datetime :created_at, null: false
    end
    add_index :login_tokens, :token_digest, unique: true
    add_index :login_tokens, :interaction_id, unique: true
    create_table :sessions do |t|
      t.references :participant, null: false, foreign_key: true
      t.datetime :expires_at, null: false
      t.timestamps
    end
    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.bigint :channel_hash, null: false
      t.index :channel
      t.index :channel_hash
      t.index :created_at
    end
  end
end
