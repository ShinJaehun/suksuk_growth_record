require "rails_helper"

RSpec.describe ClassroomsHelper, type: :helper do
  describe "#classroom_display_name" do
    it "prefixes a classroom name with its grade" do
      classroom = build(:classroom, grade: 4, class_label: "1")

      expect(helper.classroom_display_name(classroom)).to eq("4학년 1반")
    end

    it "appends the classroom suffix once" do
      classroom = build(:classroom, grade: 4, class_label: "햇살")

      expect(helper.classroom_display_name(classroom)).to eq("4학년 햇살반")
    end
  end
end
