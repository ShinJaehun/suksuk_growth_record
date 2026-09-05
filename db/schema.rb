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

ActiveRecord::Schema[8.1].define(version: 2026_09_05_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "classroom_memberships", force: :cascade do |t|
    t.bigint "classroom_id", null: false
    t.datetime "created_at", null: false
    t.string "role", default: "student", null: false
    t.string "status", default: "active", null: false
    t.integer "student_number"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["classroom_id", "student_number"], name: "idx_classroom_memberships_active_student_number", unique: true, where: "(((role)::text = 'student'::text) AND ((status)::text = 'active'::text) AND (student_number IS NOT NULL))"
    t.index ["classroom_id", "user_id"], name: "index_classroom_memberships_on_classroom_id_and_user_id", unique: true
    t.index ["classroom_id"], name: "index_classroom_memberships_on_classroom_id"
    t.index ["user_id"], name: "index_classroom_memberships_on_one_active_student", unique: true, where: "(((role)::text = 'student'::text) AND ((status)::text = 'active'::text))"
    t.index ["user_id"], name: "index_classroom_memberships_on_user_id"
    t.check_constraint "role::text = ANY (ARRAY['teacher'::character varying::text, 'student'::character varying::text])", name: "chk_cm_role"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'inactive'::character varying::text])", name: "chk_classroom_memberships_status"
    t.check_constraint "student_number IS NULL OR student_number > 0", name: "chk_classroom_memberships_student_number_positive"
  end

  create_table "classrooms", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "grade", null: false
    t.string "name"
    t.bigint "school_id", null: false
    t.string "student_login_token", null: false
    t.bigint "teacher_id"
    t.datetime "updated_at", null: false
    t.index ["school_id"], name: "index_classrooms_on_school_id"
    t.index ["student_login_token"], name: "index_classrooms_on_student_login_token", unique: true
    t.index ["teacher_id"], name: "index_classrooms_on_teacher_id", unique: true, where: "(teacher_id IS NOT NULL)"
  end

  create_table "school_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "grade"
    t.integer "role", default: 0, null: false
    t.bigint "school_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["school_id"], name: "index_school_memberships_on_school_id"
    t.index ["school_id"], name: "index_school_memberships_on_unique_manager_school", unique: true, where: "(role = 10)"
    t.index ["user_id"], name: "index_school_memberships_on_user_id", unique: true
  end

  create_table "school_years", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "school_id", null: false
    t.string "status", default: "planning", null: false
    t.datetime "updated_at", null: false
    t.integer "year", null: false
    t.index ["school_id", "year"], name: "index_school_years_on_school_id_and_year", unique: true
    t.index ["school_id"], name: "index_school_years_on_school_id"
    t.index ["school_id"], name: "index_school_years_on_unique_active_school", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["school_id"], name: "index_school_years_on_unique_planning_school", unique: true, where: "((status)::text = 'planning'::text)"
    t.check_constraint "status::text = ANY (ARRAY['planning'::character varying, 'active'::character varying, 'archived'::character varying]::text[])", name: "chk_school_years_status"
    t.check_constraint "year >= 1000 AND year <= 9999", name: "chk_school_years_year_range"
  end

  create_table "schools", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "color_key", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_schools_on_active"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "avatar_key"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "encrypted_password", default: "", null: false
    t.string "gender"
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "student", null: false
    t.string "student_pin_digest"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role", "active"], name: "index_users_on_role_and_active"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "classroom_memberships", "classrooms", on_delete: :cascade
  add_foreign_key "classroom_memberships", "users", on_delete: :cascade
  add_foreign_key "classrooms", "schools"
  add_foreign_key "classrooms", "users", column: "teacher_id"
  add_foreign_key "school_memberships", "schools"
  add_foreign_key "school_memberships", "users", on_delete: :cascade
  add_foreign_key "school_years", "schools"
end
