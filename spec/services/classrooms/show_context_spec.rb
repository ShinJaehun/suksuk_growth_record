require 'rails_helper'

RSpec.describe Classrooms::ShowContext do
  let(:classroom) { create(:classroom) }

  it 'returns active Students in roster order' do
    second = create(:student, classroom: classroom, name: '둘째', student_number: 2)
    first = create(:student, classroom: classroom, name: '첫째', student_number: 1)
    create(:student, classroom: classroom, active: false, student_number: 3)

    context = described_class.new(classroom: classroom)

    expect(context.students.to_a).to eq([first, second])
  end

  it 'returns direct Student rows with preset avatar data' do
    student = create(:student, classroom: classroom, avatar_key: 'boy01')

    loaded_student = described_class.new(classroom: classroom).students.load.first

    expect(loaded_student).to eq(student)
    expect(loaded_student.avatar_key).to eq('boy01')
  end

  it 'returns the assigned teacher' do
    teacher = create(:user, :teacher, :active_annual_teacher,
                     annual_school: classroom.school_year.school)
    assign_teacher(classroom, teacher)

    expect(described_class.new(classroom: classroom).homeroom_teacher).to eq(teacher)
  end
end
