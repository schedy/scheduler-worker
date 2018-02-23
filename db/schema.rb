# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20160411130220) do

  # These are extensions that must be enabled in order to support this database
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
