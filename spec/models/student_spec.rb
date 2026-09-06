require "rails_helper"

RSpec.describe Student, type: :model do
  describe "student number" do
    it "allows nil and positive integers" do
      expect(build(:student, student_number: nil)).to be_valid
      expect(build(:student, student_number: 1)).to be_valid
    end

    it "rejects non-positive and non-integer values" do
      [0, -1, 1.5, "number"].each do |value|
        expect(build(:student, student_number: value)).not_to be_valid
      end
    end

    it "rejects duplicate active numbers in the same classroom" do
      classroom = create(:classroom)
      create(:student, classroom: classroom, student_number: 7)

      expect(build(:student, classroom: classroom, student_number: 7)).not_to be_valid
    end

    it "allows the same number for inactive students and in other classrooms" do
      classroom = create(:classroom)
      create(:student, classroom: classroom, student_number: 7, active: false)

      expect(build(:student, classroom: classroom, student_number: 7)).to be_valid
      expect(build(:student, classroom: create(:classroom), student_number: 7)).to be_valid
    end
  end

  describe "identity" do
    it "requires a name consistent with the existing student contract" do
      expect(build(:student, name: nil)).not_to be_valid
      expect(build(:student, name: "가" * 31)).not_to be_valid
    end

    it "does not allow its classroom to change" do
      student = create(:student)

      expect(student.update(classroom: create(:classroom))).to eq(false)
      expect(student.errors[:classroom]).to be_present
    end
  end

  describe "gender" do
    it "accepts boy, girl, and nil for legacy compatibility" do
      expect(build(:student, gender: "boy")).to be_valid
      expect(build(:student, gender: "girl")).to be_valid
      expect(build(:student, gender: nil)).to be_valid
    end

    it "rejects unknown gender values" do
      expect(build(:student, gender: "other")).not_to be_valid
    end

    it "returns the avatar pool for each student gender" do
      expect(described_class.avatar_keys_for("boy")).to eq(described_class::BOY_AVATAR_KEYS)
      expect(described_class.avatar_keys_for("girl")).to eq(described_class::GIRL_AVATAR_KEYS)
      expect(described_class.avatar_keys_for(nil)).to eq([])
    end
  end

  describe "PIN and avatar" do
    it "accepts only four-digit PIN input when provided" do
      expect(build(:student, student_pin: "1234")).to be_valid
      expect(build(:student, student_pin: "123")).not_to be_valid
    end

    it "accepts existing student preset keys" do
      expect(build(:student, avatar_key: "boy01")).to be_valid
      expect(build(:student, avatar_key: "girl01")).to be_valid
      expect(build(:student, avatar_key: "teacherM01")).not_to be_valid
    end
  end
end
