require 'rails_helper'
require Rails.root.join('db/migrate/20260909001000_backfill_students_from_classroom_memberships')

RSpec.describe BackfillStudentsFromClassroomMemberships do
  subject(:migration) { described_class.new }

  around do |example|
    migration.suppress_messages { example.run }
  end

  def create_legacy_student(classroom: create(:classroom), status: 'active', student_number: 1, **user_attributes)
    user = create(
      :user,
      :student,
      { name: '학생', student_pin: '1234', avatar_key: 'boy01' }.merge(user_attributes)
    )
    membership = create(
      :classroom_membership,
      user: user,
      classroom: classroom,
      status: status,
      student_number: student_number
    )

    [user, membership]
  end

  it 'backfills each student membership with the canonical values' do
    user, membership = create_legacy_student(student_number: 7, name: '김학생', avatar_key: 'girl01')

    migration.migrate(:up)

    student = Student.find_by!(classroom_id: membership.classroom_id)
    expect(student.attributes.slice(
             'name', 'student_number', 'active', 'student_pin_digest', 'avatar_key'
           )).to eq(
             'name' => '김학생',
             'student_number' => 7,
             'active' => true,
             'student_pin_digest' => user.student_pin_digest,
             'avatar_key' => 'girl01'
           )
  end

  it 'creates independent Students for multiple memberships of one User' do
    user, first_membership = create_legacy_student
    second_membership = create(
      :classroom_membership,
      user: user,
      classroom: create(:classroom),
      status: 'inactive',
      student_number: 2
    )

    migration.migrate(:up)

    expect(Student.where(classroom_id: [first_membership.classroom_id, second_membership.classroom_id]).count).to eq(2)
  end

  it 'copies inactive status and allows a nil student number' do
    _, membership = create_legacy_student(status: 'inactive', student_number: nil)

    migration.migrate(:up)

    student = Student.find_by!(classroom_id: membership.classroom_id)
    expect(student).to be_inactive
    expect(student.student_number).to be_nil
  end

  it 'fails for an orphan student User' do
    create(:user, :student, student_pin: '1234')

    expect { migration.migrate(:up) }.to raise_error(ActiveRecord::MigrationError, /no student ClassroomMembership/)
  end

  it 'fails when a student has no PIN digest' do
    create_legacy_student(student_pin: nil)

    expect { migration.migrate(:up) }.to raise_error(ActiveRecord::MigrationError, /no PIN digest/)
  end

  it 'fails for an invalid student number' do
    _, membership = create_legacy_student
    allow(migration).to receive(:select_value).and_call_original
    allow(migration).to receive(:select_value)
      .with(a_string_matching(/student_number < 1/)).and_return(membership.id)

    expect { migration.migrate(:up) }.to raise_error(ActiveRecord::MigrationError, /invalid student number/)
  end

  it 'fails for duplicate active student numbers' do
    _, membership = create_legacy_student
    allow(migration).to receive(:select_value).and_call_original
    allow(migration).to receive(:select_value)
      .with(a_string_matching(/HAVING COUNT\(\*\) > 1/)).and_return(membership.classroom_id)

    expect { migration.migrate(:up) }.to raise_error(ActiveRecord::MigrationError, /duplicate active student numbers/)
  end

  it 'fails when a classroom has more than 30 active students' do
    classroom = create(:classroom)
    31.times do |number|
      create_legacy_student(classroom: classroom, student_number: number + 1)
    end

    expect { migration.migrate(:up) }.to raise_error(ActiveRecord::MigrationError, /more than 30 active students/)
  end

  it 'fails for an invalid student avatar key' do
    user, = create_legacy_student
    user.update_columns(avatar_key: 'teacherM01')

    expect { migration.migrate(:up) }.to raise_error(ActiveRecord::MigrationError, /invalid avatar key/)
  end

  it 'fails when a student has a custom avatar attachment' do
    user, = create_legacy_student
    user.avatar.attach(io: StringIO.new('avatar'), filename: 'avatar.txt', content_type: 'text/plain')

    expect { migration.migrate(:up) }.to raise_error(ActiveRecord::MigrationError, /custom avatar attachment/)
  end

  it 'ignores teacher and admin custom avatars' do
    create_legacy_student
    [create(:user, :teacher, :active_annual_teacher, annual_school: create(:school)),
     create(:user, :admin)].each do |user|
      user.avatar.attach(io: StringIO.new('avatar'), filename: 'avatar.txt', content_type: 'text/plain')
    end

    expect { migration.migrate(:up) }.to change(Student, :count).by(1)
  end

  it 'fails when the students table is not empty' do
    create(:student)
    create_legacy_student

    expect { migration.migrate(:up) }.to raise_error(ActiveRecord::MigrationError, /students table is not empty/)
  end

  it 'does not insert any Student when preflight fails' do
    create_legacy_student
    create_legacy_student(student_pin: nil)

    expect { migration.migrate(:up) }.to raise_error(ActiveRecord::MigrationError)
    expect(Student.count).to eq(0)
  end

  it 'is irreversible' do
    expect { migration.migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
