class RemoveServiceSpecificDomains < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      DELETE FROM active_storage_attachments
      WHERE record_type = 'CouponTemplate'
    SQL

    drop_table :student_activity_notes
    drop_table :coupon_use_requests
    drop_table :coupon_events
    drop_table :user_messages
    drop_table :compliments
    drop_table :user_coupons
    drop_table :compliment_presets
    drop_table :coupon_templates
    drop_table :school_closures
    drop_table :public_holidays

    remove_column :users, :points, :integer
    remove_column :classrooms, :daily_compliment_king_enabled, :boolean
    remove_column :classrooms, :weekly_compliment_king_enabled, :boolean
    remove_column :classrooms, :monthly_compliment_king_enabled, :boolean
    remove_column :classrooms, :message_policy, :string
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
