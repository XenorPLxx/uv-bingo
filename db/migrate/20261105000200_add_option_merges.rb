class AddOptionMerges < ActiveRecord::Migration[8.1]
  def change
    add_reference :options, :merged_into, null: true
    add_foreign_key :options, :options, column: [ :merged_into_id, :event_id ], primary_key: [ :id, :event_id ], name: "merged_options_same_event"
    add_check_constraint :options, "merged_into_id IS NULL OR merged_into_id <> id", name: "options_cannot_merge_into_self"
  end
end
