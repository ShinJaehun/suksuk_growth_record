require 'rails_helper'

RSpec.describe ClassroomStudents::BulkRegistration do
  let(:classroom) { create(:classroom) }
  let(:rows) do
    {
      'first' => {
        student_number: '1',
        name: '첫 학생',
        gender: 'girl',
        avatar_key: 'girl01'
      },
      'second' => {
        student_number: '2',
        name: '둘 학생',
        gender: 'boy',
        avatar_key: 'boy01'
      }
    }
  end

  def call_workflow(submitted_rows = rows)
    described_class.call(
      classroom: classroom,
      student_pin: '2468',
      rows: submitted_rows
    )
  end

  it 'creates every Student with gender, avatar, number, and PIN' do
    result = call_workflow

    expect(result).to be_success
    expect(result.students.map { |student| student.attributes.values_at('name', 'gender', 'avatar_key') }).to eq(
      [['첫 학생', 'girl', 'girl01'], ['둘 학생', 'boy', 'boy01']]
    )
    expect(classroom.students.pluck(:student_number)).to contain_exactly(1, 2)
    expect(result.students).to all(satisfy { |student| student.authenticate_student_pin('2468') })
    expect(ClassroomMembership.where(classroom: classroom).student).to be_empty
    expect(User.student.where(name: ['첫 학생', '둘 학생'])).to be_empty
  end

  it 'rejects duplicate student numbers within the submitted roster' do
    rows['second'][:student_number] = '1'
    result = nil

    expect { result = call_workflow }.not_to change(Student, :count)

    expect(result).not_to be_success
    expect(result.row_errors.keys).to contain_exactly('first', 'second')
  end

  it 'rejects a student number used by an active student' do
    create(:student, classroom: classroom, active: true, student_number: 1)

    result = call_workflow

    expect(result).not_to be_success
    expect(result.row_errors['first']).to include(
      I18n.t('students.bulk_create.errors.student_number_taken', number: '1')
    )
    expect(Student.where(name: ['첫 학생', '둘 학생'])).to be_empty
  end

  it 'rejects a roster that would exceed the active student limit' do
    Classroom::MAX_ACTIVE_STUDENTS.times do |index|
      create(:student, classroom: classroom, active: true, student_number: nil, name: "기존 학생 #{index}")
    end

    result = call_workflow

    expect(result).not_to be_success
    expect(result.error).to eq(
      I18n.t('students.bulk_create.errors.too_many', count: Classroom::MAX_ACTIVE_STUDENTS)
    )
    expect(Student.where(name: ['첫 학생', '둘 학생'])).to be_empty
  end

  it 'rolls back every row when a later Student save fails' do
    calls = 0
    allow_any_instance_of(Student).to receive(:save!).and_wrap_original do |method|
      calls += 1
      if calls == 2
        method.receiver.errors.add(:base, 'student failed')
        raise ActiveRecord::RecordInvalid.new(method.receiver)
      end

      method.call
    end

    result = call_workflow

    expect(result).not_to be_success
    expect(Student.where(name: ['첫 학생', '둘 학생'])).to be_empty
  end

  it 'requires boy or girl for every submitted student' do
    rows['first'][:gender] = 'other'

    result = call_workflow

    expect(result).not_to be_success
    expect(result.row_errors['first']).to include(
      I18n.t('students.bulk_create.errors.gender_required')
    )
    expect(Student.where(name: ['첫 학생', '둘 학생'])).to be_empty
  end

  it 'rejects an avatar that does not match the submitted gender' do
    rows['first'][:avatar_key] = 'boy01'

    result = call_workflow

    expect(result).not_to be_success
    expect(result.row_errors['first']).to include(
      I18n.t('students.bulk_create.errors.invalid_avatar')
    )
    expect(Student.where(name: ['첫 학생', '둘 학생'])).to be_empty
  end

  it 'returns a failure result when the database reports a unique conflict' do
    allow_any_instance_of(Student).to receive(:save!)
      .and_raise(ActiveRecord::RecordNotUnique)

    result = call_workflow

    expect(result).not_to be_success
    expect(result.error).to eq(
      I18n.t('students.bulk_create.errors.student_number_taken', number: '1')
    )
    expect(Student.where(name: ['첫 학생', '둘 학생'])).to be_empty
  end

  it 'preserves normalized rows and row errors in a failed result' do
    rows['first'][:student_number] = 'abc'
    rows['first'][:name] = ''

    result = call_workflow

    expect(result).not_to be_success
    expect(result.rows.first).to include(
      index: 'first',
      student_number: 'abc',
      name: '',
      gender: 'girl',
      avatar_key: 'girl01'
    )
    expect(result.row_errors['first']).to include(
      I18n.t('students.create.errors.student_number_invalid'),
      I18n.t('students.bulk_create.errors.name_required')
    )
  end
end
