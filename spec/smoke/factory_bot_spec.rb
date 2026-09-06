require "rails_helper"

RSpec.describe "FactoryBot smoke", type: :model do
  it "builds a valid user factory" do
    user = build(:user, :admin)

    expect(user).to be_valid
    expect(user.role).to eq("admin")
  end
end
