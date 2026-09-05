require 'rails_helper'

RSpec.describe AnnualTeacherUsers::MappingBackfill do
  def mapping_row(teacher, login_id: 'tara0411')
    { teacher_user_id: teacher.id, login_id: login_id }
  end

  def error_codes(result)
    result.errors.map(&:code)
  end

  def active_school_year(school = create(:school), year: 2026)
    create(:school_year, :active, school: school, year: year)
  end

  def teacher_with_membership(school:, role: :member, grade: 4)
    teacher = create(:user, :teacher)
    create(:school_membership, user: teacher, school: school, role: role, grade: grade)
    teacher
  end

  it 'maps explicit identity fields and projects role and grade from SchoolMembership' do
    school_year = active_school_year
    teacher = teacher_with_membership(school: school_year.school, role: :manager, grade: 4)

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [mapping_row(teacher)]
    )

    expect(result).to be_success
    expect(result.mapped_count).to eq(1)
    expect(teacher.reload).to have_attributes(
      school_year_id: school_year.id,
      login_id: 'tara0411',
      school_role: 'manager',
      grade: 4
    )
  end

  it 'allows a nil membership grade' do
    school_year = active_school_year
    teacher = teacher_with_membership(school: school_year.school, grade: nil)

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [mapping_row(teacher)]
    )

    expect(result).to be_success
    expect(teacher.reload.grade).to be_nil
  end

  it 'treats an identical completed mapping as an idempotent no-op' do
    school_year = active_school_year
    teacher = teacher_with_membership(school: school_year.school, grade: 4)
    row = mapping_row(teacher)

    first_result = described_class.call(target_school_year_id: school_year.id, rows: [row])
    second_result = described_class.call(target_school_year_id: school_year.id, rows: [row])

    expect(first_result.mapped_count).to eq(1)
    expect(second_result).to be_success
    expect(second_result.mapped_count).to eq(0)
    expect(second_result.already_mapped_count).to eq(1)
  end

  it 'does not count an identical already-mapped manager twice' do
    school_year = active_school_year
    teacher = teacher_with_membership(school: school_year.school, role: :manager)
    teacher.update_columns(
      school_year_id: school_year.id,
      login_id: 'tara0411',
      school_role: 'manager',
      grade: 4
    )

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [mapping_row(teacher)]
    )

    expect(result).to be_success
    expect(result.already_mapped_count).to eq(1)
  end

  it 'allows the same login ID in separate SchoolYear batches' do
    first_year = active_school_year(create(:school), year: 2025)
    second_year = active_school_year(create(:school), year: 2026)
    first_teacher = teacher_with_membership(school: first_year.school)
    second_teacher = teacher_with_membership(school: second_year.school)

    first_result = described_class.call(
      target_school_year_id: first_year.id,
      rows: [mapping_row(first_teacher)]
    )
    second_result = described_class.call(
      target_school_year_id: second_year.id,
      rows: [mapping_row(second_teacher)]
    )

    expect(first_result).to be_success
    expect(second_result).to be_success
  end

  it 'validates a dry run without mutating annual fields' do
    school_year = active_school_year
    teacher = teacher_with_membership(school: school_year.school)

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [mapping_row(teacher)],
      dry_run: true
    )

    expect(result).to be_success
    expect(result.mapped_count).to eq(1)
    expect(teacher.reload).to have_attributes(
      school_year_id: nil,
      login_id: nil,
      school_role: nil,
      grade: nil
    )
  end

  it 'rejects a malformed mapping row' do
    school_year = active_school_year

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: ['not-a-mapping']
    )

    expect(error_codes(result)).to include(:malformed_mapping_row)
  end

  it 'revalidates current membership state on a real run after dry-run' do
    school_year = active_school_year
    teacher = teacher_with_membership(school: school_year.school)
    row = mapping_row(teacher)
    dry_run = described_class.call(
      target_school_year_id: school_year.id,
      rows: [row],
      dry_run: true
    )
    teacher.school_membership.update!(school: create(:school))

    real_run = described_class.call(target_school_year_id: school_year.id, rows: [row])

    expect(dry_run).to be_success
    expect(real_run).not_to be_success
    expect(error_codes(real_run)).to include(:school_mismatch)
    expect(teacher.reload.school_year_id).to be_nil
  end

  it 'rejects a missing or non-active target SchoolYear' do
    teacher = create(:user, :teacher)
    planning_year = create(:school_year)
    missing_school_year_id = SchoolYear.maximum(:id).to_i + 1

    missing = described_class.call(
      target_school_year_id: missing_school_year_id,
      rows: [mapping_row(teacher)]
    )
    planning = described_class.call(target_school_year_id: planning_year.id, rows: [mapping_row(teacher)])

    expect(error_codes(missing)).to include(:target_school_year_not_found)
    expect(error_codes(planning)).to include(:target_school_year_not_active)
  end

  it 'rejects an unknown User' do
    school_year = active_school_year

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [{ teacher_user_id: User.maximum(:id).to_i + 1, login_id: 'tara0411' }]
    )

    expect(error_codes(result)).to include(:teacher_not_found)
  end

  it 'rejects admin and student Users' do
    school_year = active_school_year
    admin = create(:user, :admin)
    student = create(:user, :student)

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [mapping_row(admin), mapping_row(student, login_id: 'student01')]
    )

    expect(error_codes(result)).to include(:user_not_teacher)
    expect(admin.reload.school_year_id).to be_nil
    expect(student.reload.school_year_id).to be_nil
  end

  it 'rejects a missing membership and a school mismatch' do
    school_year = active_school_year
    teacher_without_membership = create(:user, :teacher)
    other_teacher = teacher_with_membership(school: create(:school))

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [
        mapping_row(teacher_without_membership),
        mapping_row(other_teacher, login_id: 'apple09')
      ]
    )

    expect(error_codes(result)).to include(:school_membership_missing, :school_mismatch)
  end

  it 'rejects duplicate User and login ID input' do
    school_year = active_school_year
    first_teacher = teacher_with_membership(school: school_year.school)
    second_teacher = teacher_with_membership(school: school_year.school)

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [
        mapping_row(first_teacher),
        mapping_row(first_teacher, login_id: 'apple09'),
        mapping_row(second_teacher)
      ]
    )

    expect(error_codes(result)).to include(:duplicate_teacher_user_id, :duplicate_login_id)
  end

  it 'rejects blank and surrounding-whitespace login IDs without normalization' do
    school_year = active_school_year
    teacher = teacher_with_membership(school: school_year.school)

    ['', '   ', ' tara0411', 'tara0411 '].each do |login_id|
      result = described_class.call(
        target_school_year_id: school_year.id,
        rows: [mapping_row(teacher, login_id: login_id)]
      )

      expect(error_codes(result)).to include(:invalid_login_id)
    end
    expect(teacher.reload.login_id).to be_nil
  end

  it 'rejects a login ID owned by another User in the target SchoolYear' do
    school_year = active_school_year
    owner = teacher_with_membership(school: school_year.school)
    candidate = teacher_with_membership(school: school_year.school)
    owner.update_columns(
      school_year_id: school_year.id,
      login_id: 'tara0411',
      school_role: 'member',
      grade: 4
    )

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [mapping_row(candidate)]
    )

    expect(error_codes(result)).to include(:login_id_collision)
    expect(candidate.reload.school_year_id).to be_nil
  end

  it 'rejects a manager projected for a SchoolYear with another shadow manager' do
    school_year = active_school_year
    existing_manager = create(:user, :teacher)
    existing_manager.update_columns(
      school_year_id: school_year.id,
      login_id: 'existing01',
      school_role: 'manager',
      grade: nil
    )
    candidate = teacher_with_membership(school: school_year.school, role: :manager)

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [mapping_row(candidate)]
    )

    expect(error_codes(result)).to include(:manager_conflict)
    expect(candidate.reload.school_year_id).to be_nil
  end

  it 'rejects partial, different, and drifted shadow states' do
    school_year = active_school_year
    partial = teacher_with_membership(school: school_year.school)
    different = teacher_with_membership(school: school_year.school)
    drifted = teacher_with_membership(school: school_year.school, grade: 4)
    partial.update_columns(school_year_id: school_year.id)
    different.update_columns(
      school_year_id: school_year.id,
      login_id: 'other01',
      school_role: 'member',
      grade: 4
    )
    drifted.update_columns(
      school_year_id: school_year.id,
      login_id: 'drift01',
      school_role: 'member',
      grade: 5
    )

    result = described_class.call(
      target_school_year_id: school_year.id,
      rows: [
        mapping_row(partial, login_id: 'partial01'),
        mapping_row(different, login_id: 'requested01'),
        mapping_row(drifted, login_id: 'drift01')
      ]
    )

    expect(error_codes(result)).to include(:conflicting_shadow_state)
  end

  it 'rolls back every mapping when one persistence operation fails' do
    school_year = active_school_year
    first_teacher = teacher_with_membership(school: school_year.school)
    second_teacher = teacher_with_membership(school: school_year.school)
    service = described_class.new(
      target_school_year_id: school_year.id,
      rows: [
        mapping_row(first_teacher),
        mapping_row(second_teacher, login_id: 'apple09')
      ]
    )
    update_count = 0
    allow(service).to receive(:persist_projection).and_wrap_original do |method, projection|
      update_count += 1
      raise ActiveRecord::StatementInvalid, 'forced failure' if update_count == 2

      method.call(projection)
    end

    result = service.call

    expect(result).not_to be_success
    expect(first_teacher.reload.school_year_id).to be_nil
    expect(second_teacher.reload.school_year_id).to be_nil
  end
end
