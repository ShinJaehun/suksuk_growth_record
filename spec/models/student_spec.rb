require 'rails_helper'

RSpec.describe Student, type: :model do
  describe 'student number' do
    it 'allows nil and positive integers' do
      expect(build(:student, student_number: nil)).to be_valid
      expect(build(:student, student_number: 1)).to be_valid
    end

    it 'rejects non-positive and non-integer values' do
      [0, -1, 1.5, 'number'].each do |value|
        expect(build(:student, student_number: value)).not_to be_valid
      end
    end

    it 'rejects duplicate active numbers in the same classroom' do
      classroom = create(:classroom)
      create(:student, classroom: classroom, student_number: 7)

      expect(build(:student, classroom: classroom, student_number: 7)).not_to be_valid
    end

    it 'enforces duplicate active numbers at the database level' do
      classroom = create(:classroom)
      now = Time.current

      described_class.insert!({
                                classroom_id: classroom.id,
                                name: '첫 학생',
                                student_number: 7,
                                active: true,
                                created_at: now,
                                updated_at: now
                              })

      expect do
        described_class.insert!({
                                  classroom_id: classroom.id,
                                  name: '둘째 학생',
                                  student_number: 7,
                                  active: true,
                                  created_at: now,
                                  updated_at: now
                                })
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same number for inactive students and in other classrooms' do
      classroom = create(:classroom)
      create(:student, classroom: classroom, student_number: 7, active: false)

      expect(build(:student, classroom: classroom, student_number: 7)).to be_valid
      expect(build(:student, classroom: create(:classroom), student_number: 7)).to be_valid
    end

    it 'allows inactive students to share a number' do
      classroom = create(:classroom)
      create(:student, classroom: classroom, student_number: 7, active: false)

      expect(build(:student, classroom: classroom, student_number: 7, active: false)).to be_valid
    end
  end

  describe '.in_roster_order' do
    it 'orders numbered students first and unnumbered students by name and id' do
      classroom = create(:classroom)
      number_five = create(:student, classroom: classroom, name: '다섯', student_number: 5)
      unnumbered_second = create(:student, classroom: classroom, name: 'Unnumbered B', student_number: nil)
      number_one = create(:student, classroom: classroom, name: '하나', student_number: 1)
      number_two = create(:student, classroom: classroom, name: '둘', student_number: 2)
      unnumbered_first = create(:student, classroom: classroom, name: 'Unnumbered A', student_number: nil)

      expect(classroom.students.in_roster_order).to eq([
                                                         number_one,
                                                         number_two,
                                                         number_five,
                                                         unnumbered_first,
                                                         unnumbered_second
                                                       ])
    end

    it 'uses ids as stable ties for unnumbered students with the same name' do
      classroom = create(:classroom)
      first_student = create(:student, classroom: classroom, name: 'Same Name', student_number: nil)
      second_student = create(:student, classroom: classroom, name: 'Same Name', student_number: nil)

      expect(
        described_class.where(id: [second_student.id, first_student.id]).in_roster_order.pluck(:id)
      ).to eq([first_student.id, second_student.id])
    end
  end

  describe 'identity' do
    it 'requires a name consistent with the existing student contract' do
      expect(build(:student, name: nil)).not_to be_valid
      expect(build(:student, name: '가' * 31)).not_to be_valid
    end

    it 'does not allow its classroom to change' do
      student = create(:student)

      expect(student.update(classroom: create(:classroom))).to eq(false)
      expect(student.errors[:classroom]).to be_present
    end
  end

  describe 'lifecycle' do
    it 'supports active and inactive student records' do
      active_student = create(:student, active: true)
      inactive_student = create(:student, active: false)

      expect(active_student).to be_active
      expect(inactive_student).to be_inactive
    end
  end

  describe 'gender' do
    it 'accepts boy, girl, and nil for legacy compatibility' do
      expect(build(:student, gender: 'boy')).to be_valid
      expect(build(:student, gender: 'girl')).to be_valid
      expect(build(:student, gender: nil)).to be_valid
    end

    it 'rejects unknown gender values' do
      expect(build(:student, gender: 'other')).not_to be_valid
    end

    it 'returns the avatar pool for each student gender' do
      expect(described_class.avatar_keys_for('boy')).to eq(described_class::BOY_AVATAR_KEYS)
      expect(described_class.avatar_keys_for('girl')).to eq(described_class::GIRL_AVATAR_KEYS)
      expect(described_class.avatar_keys_for(nil)).to eq([])
    end
  end

  describe 'PIN and avatar' do
    it 'accepts only four-digit PIN input when provided' do
      expect(build(:student, student_pin: '1234')).to be_valid
      expect(build(:student, student_pin: '123')).not_to be_valid
    end

    it 'accepts existing student preset keys' do
      expect(build(:student, avatar_key: 'boy01')).to be_valid
      expect(build(:student, avatar_key: 'girl01')).to be_valid
      expect(build(:student, avatar_key: 'teacherM01')).not_to be_valid
    end
  end
end
