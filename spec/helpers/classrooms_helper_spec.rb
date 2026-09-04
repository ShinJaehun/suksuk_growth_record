require "rails_helper"

RSpec.describe ClassroomsHelper, type: :helper do
  describe "#classroom_display_name" do
    it "prefixes a classroom name with its grade" do
      classroom = build(:classroom, grade: 4, name: "1반")

      expect(helper.classroom_display_name(classroom)).to eq("4학년 1반")
    end

    it "does not duplicate an existing grade prefix" do
      classroom = build(:classroom, grade: 4, name: "4학년 1반")

      expect(helper.classroom_display_name(classroom)).to eq("4학년 1반")
    end
  end
end
