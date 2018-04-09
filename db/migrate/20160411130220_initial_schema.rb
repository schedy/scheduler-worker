class InitialSchema < ActiveRecord::Migration
  def change

  enable_extension "plpgsql"

  create_table "resources", force: :cascade do |t|
    t.integer  "task_id"
    t.jsonb    "description"
    t.datetime "created_at",  null: false
    t.datetime "updated_at",  null: false
    t.integer  "parent_id"
  end

  create_table "statistics", force: :cascade do |t|
    t.text     "action",                     default: [],              array: true
    t.integer  "average_duration", limit: 8
    t.datetime "created_at",                              null: false
    t.datetime "updated_at",                              null: false
    t.integer  "occurence",        limit: 8
  end

  create_table "statistics_archive", force: :cascade do |t|
    t.text     "action",               default: [],              array: true
    t.integer  "duration",   limit: 8
    t.datetime "created_at",                        null: false
    t.datetime "updated_at",                        null: false
  end

  create_table "tasks", force: :cascade do |t|
    t.text     "status"
    t.integer  "pid"
    t.datetime "cleaned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_index "tasks", ["id"], name: "tasks_id_idx", where: "((pid IS NOT NULL) AND (cleaned_at IS NULL))", using: :btree

  end
end
