class AddGradeToSchoolMemberships < ActiveRecord::Migration[7.1]
  def change
    add_column :school_memberships, :grade, :integer
  end
end
