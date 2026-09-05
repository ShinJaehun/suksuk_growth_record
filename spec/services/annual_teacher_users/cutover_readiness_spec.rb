require "rails_helper"

RSpec.describe AnnualTeacherUsers::CutoverReadiness do
  def annual_teacher(school_year:, login_id:, school_role: "member", grade: nil)
    create(:user, :teacher, school_year:, login_id:, school_role:, grade:)
  end

  it "reconciles role and grade for the mapped legacy cohort" do
    school = create(:school)
    school_year = create(:school_year, :active, school:)
    teacher = annual_teacher(school_year:, login_id: "teacher1", school_role: "member", grade: 1)
    create(:school_membership, :manager, school:, user: teacher, grade: 2)

    result = described_class.call(dry_run: false)

    expect(result).to be_ready
    expect(teacher.reload).to have_attributes(school_role: "manager", grade: 2)
  end

  it "allows a pure annual planning teacher without a membership" do
    school_year = create(:school_year)
    annual_teacher(school_year:, login_id: "planning1")

    expect(described_class.call).to be_ready
  end

  it "does not change annual identity mapping" do
    school = create(:school)
    school_year = create(:school_year, :active, school:)
    teacher = annual_teacher(school_year:, login_id: "teacher1")
    create(:school_membership, school: create(:school), user: teacher)

    result = described_class.call(dry_run: false)

    expect(result).not_to be_ready
    expect(teacher.reload).to have_attributes(school_year_id: school_year.id, login_id: "teacher1")
  end

  it "normalizes collision-free uppercase login IDs" do
    teacher = annual_teacher(school_year: create(:school_year), login_id: "Tara")

    expect(described_class.call(dry_run: false)).to be_ready
    expect(teacher.reload.login_id).to eq("tara")
  end

  it "rejects case-fold collisions without changing either login ID" do
    school_year = create(:school_year)
    first = annual_teacher(school_year:, login_id: "Tara")
    second = annual_teacher(school_year:, login_id: "tara")

    result = described_class.call(dry_run: false)

    expect(result).not_to be_ready
    expect([first.reload.login_id, second.reload.login_id]).to contain_exactly("Tara", "tara")
  end

  it "rejects stored whitespace rather than stripping it" do
    teacher = annual_teacher(school_year: create(:school_year), login_id: " tara ")

    expect(described_class.call(dry_run: false)).not_to be_ready
    expect(teacher.reload.login_id).to eq(" tara ")
  end

  it "keeps a committed reconciliation while reporting a later global blocker" do
    school = create(:school)
    school_year = create(:school_year, :active, school:)
    legacy = annual_teacher(school_year:, login_id: "legacy", grade: 1)
    create(:school_membership, school:, user: legacy, grade: 2)
    annual_teacher(school_year: create(:school_year), login_id: " invalid ")

    result = described_class.call(dry_run: false)

    expect(result).not_to be_ready
    expect(result.reconciled_count).to eq(1)
    expect(legacy.reload.grade).to eq(2)
  end

  it "rolls back every change within a failing SchoolYear batch" do
    school = create(:school)
    school_year = create(:school_year, :active, school:)
    valid = annual_teacher(school_year:, login_id: "valid", grade: 1)
    invalid = annual_teacher(school_year:, login_id: "invalid")
    create(:school_membership, school:, user: valid, grade: 2)
    create(:school_membership, school: create(:school), user: invalid)

    result = described_class.call(dry_run: false)

    expect(result).not_to be_ready
    expect(valid.reload.grade).to eq(1)
    expect(result.reconciled_count).to eq(0)
  end

  it "projects changes and counts without locking or writing in dry-run" do
    school = create(:school)
    school_year = create(:school_year, :active, school:)
    teacher = annual_teacher(school_year:, login_id: "Tara", grade: 1)
    create(:school_membership, school:, user: teacher, grade: 2)

    result = described_class.call(dry_run: true)

    expect(result).to be_ready
    expect(result).to have_attributes(reconciled_count: 1, normalized_count: 1)
    expect(teacher.reload).to have_attributes(grade: 1, login_id: "Tara")
  end

  it "does not count writes rolled back by a persistence failure" do
    school = create(:school)
    school_year = create(:school_year, :active, school:)
    first = annual_teacher(school_year:, login_id: "first", grade: 1)
    second = annual_teacher(school_year:, login_id: "second", grade: 1)
    create(:school_membership, school:, user: first, grade: 2)
    create(:school_membership, school:, user: second, grade: 3)
    allow_any_instance_of(User).to receive(:update_columns).and_wrap_original do |method, attributes|
      raise ActiveRecord::StatementInvalid, "failure" if method.receiver.id == second.id

      method.call(attributes)
    end

    result = described_class.call(dry_run: false)

    expect(result).not_to be_ready
    expect(result.reconciled_count).to eq(0)
    expect(first.reload.grade).to eq(1)
  end
end
