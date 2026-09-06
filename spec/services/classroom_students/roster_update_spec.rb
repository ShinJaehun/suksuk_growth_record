require "rails_helper"

RSpec.describe ClassroomStudents::RosterUpdate do
  let(:classroom) { create(:classroom) }

  def create_student(number:, active: true, **attributes)
    create(
      :student,
      {
        classroom: classroom,
        student_number: number,
        active: active,
        gender: "boy",
        avatar_key: "boy01"
      }.merge(attributes)
    )
  end

  def call_workflow(students:, rows:)
    described_class.call(
      classroom: classroom,
      students: students,
      rows: rows
    )
  end

  it "updates student number, name, gender, and avatar together" do
    student = create_student(number: 1, name: "수정 전")

    result = call_workflow(
      students: [student],
      rows: {
        student.id => {
          student_number: "7",
          name: "수정 후",
          gender: "girl",
          avatar_key: "girl02"
        }
      }
    )

    expect(result).to be_success
    expect(student.reload.attributes.values_at("student_number", "name", "gender", "avatar_key")).to eq(
      [7, "수정 후", "girl", "girl02"]
    )
  end

  it "stores a blank student number as nil" do
    student = create_student(number: 7)

    result = call_workflow(
      students: [student],
      rows: { student.id => { student_number: "", name: student.name } }
    )

    expect(result).to be_success
    expect(student.reload.student_number).to be_nil
  end

  it "rejects duplicate final numbers among edited active students" do
    first = create_student(number: 1)
    second = create_student(number: 2)

    result = call_workflow(
      students: [first, second],
      rows: {
        first.id => { student_number: "2", name: first.name },
        second.id => { student_number: "2", name: second.name }
      }
    )

    expect(result).not_to be_success
    expect(result.row_errors.keys).to contain_exactly(first.id.to_s, second.id.to_s)
    expect([first, second].map { |student| student.reload.student_number }).to eq([1, 2])
  end

  it "rejects a number used by an unedited active student" do
    student = create_student(number: 1)
    unedited_student = create_student(number: 2)

    result = call_workflow(
      students: [student],
      rows: { student.id => { student_number: "2", name: student.name } }
    )

    expect(result).not_to be_success
    expect(result.row_errors[student.id.to_s]).to include(
      I18n.t("students.members.update_names.duplicate_student_number", number: 2)
    )
    expect(student.reload.student_number).to eq(1)
    expect(unedited_student.reload.student_number).to eq(2)
  end

  it "swaps two active student numbers" do
    first = create_student(number: 1)
    second = create_student(number: 2)

    result = call_workflow(
      students: [first, second],
      rows: {
        first.id => { student_number: "2", name: first.name },
        second.id => { student_number: "1", name: second.name }
      }
    )

    expect(result).to be_success
    expect([first, second].map { |student| student.reload.student_number }).to eq([2, 1])
  end

  it "supports an active student number cycle" do
    students = [1, 2, 3].map { |number| create_student(number: number) }
    rows = students.each_with_index.to_h do |student, index|
      [student.id, { student_number: [2, 3, 1][index].to_s, name: student.name }]
    end

    result = call_workflow(students: students, rows: rows)

    expect(result).to be_success
    expect(students.map { |student| student.reload.student_number }).to eq([2, 3, 1])
  end

  it "rejects a Student outside the supplied editable collection" do
    student = create_student(number: 1)
    other_student = create_student(number: 2)

    result = call_workflow(
      students: [student],
      rows: {
        student.id => { name: "변경 금지" },
        other_student.id => { name: "외부 변경 금지" }
      }
    )

    expect(result).not_to be_success
    expect(result.error_key).to eq(:invalid_membership)
    expect(student.reload.name).not_to eq("변경 금지")
    expect(other_student.reload.name).not_to eq("외부 변경 금지")
  end

  it "rolls back all Student changes when a later save fails" do
    first = create_student(number: 1, name: "첫 원본")
    second = create_student(number: 2, name: "둘 원본")
    calls = 0
    allow_any_instance_of(Student).to receive(:save!).and_wrap_original do |method|
      calls += 1
      if calls == 2
        method.receiver.errors.add(:base, "student failed")
        raise ActiveRecord::RecordInvalid.new(method.receiver)
      end

      method.call
    end

    result = call_workflow(
      students: [first, second],
      rows: {
        first.id => { student_number: "2", name: "첫 변경" },
        second.id => { student_number: "1", name: "둘 변경" }
      }
    )

    expect(result).not_to be_success
    expect([first, second].map { |student| student.reload.name }).to eq(["첫 원본", "둘 원본"])
    expect([first, second].map(&:student_number)).to eq([1, 2])
  end

  it "preserves a legacy mismatched avatar when gender is unchanged" do
    student = create_student(number: 7, name: "기존")
    student.update_column(:avatar_key, "girl01")

    result = call_workflow(
      students: [student],
      rows: {
        student.id => {
          student_number: "8",
          name: "수정",
          gender: "boy",
          avatar_key: "girl01"
        }
      }
    )

    expect(result).to be_success
    expect(student.reload.attributes.values_at("student_number", "name", "gender", "avatar_key")).to eq(
      [8, "수정", "boy", "girl01"]
    )
  end

  it "rejects a different mismatched avatar when gender is unchanged" do
    student = create_student(number: 7, name: "기존")

    result = call_workflow(
      students: [student],
      rows: {
        student.id => {
          student_number: "8",
          name: "변경 금지",
          gender: "boy",
          avatar_key: "girl07"
        }
      }
    )

    expect(result).not_to be_success
    expect(result.row_errors[student.id.to_s]).to include(
      I18n.t("students.members.update_names.invalid_avatar")
    )
    expect(student.reload.attributes.values_at("student_number", "name", "gender", "avatar_key")).to eq(
      [7, "기존", "boy", "boy01"]
    )
  end

  it "keeps a submitted valid avatar after a gender change" do
    student = create_student(number: 1)

    result = call_workflow(
      students: [student],
      rows: {
        student.id => {
          name: student.name,
          gender: "girl",
          avatar_key: "girl03"
        }
      }
    )

    expect(result).to be_success
    expect(student.reload.attributes.values_at("gender", "avatar_key")).to eq(["girl", "girl03"])
  end

  it "uses a deterministic matching avatar when gender changes without a new avatar" do
    first = create_student(number: 1)
    second = create_student(number: 2)

    result = call_workflow(
      students: [first, second],
      rows: {
        second.id => {
          name: second.name,
          gender: "girl",
          avatar_key: "boy01"
        }
      }
    )

    expect(result).to be_success
    expect(second.reload.gender).to eq("girl")
    expect(second.avatar_key).to eq(Student::GIRL_AVATAR_KEYS[1])
  end

  it "allows unrelated updates for a legacy Student without gender" do
    student = create_student(number: 1, gender: nil, avatar_key: "boy01", name: "기존")

    result = call_workflow(
      students: [student],
      rows: { student.id => { name: "수정" } }
    )

    expect(result).to be_success
    expect(student.reload.attributes.values_at("name", "gender", "avatar_key")).to eq(
      ["수정", nil, "boy01"]
    )
  end

  it "rejects an invalid submitted gender" do
    student = create_student(number: 1)

    result = call_workflow(
      students: [student],
      rows: {
        student.id => {
          name: student.name,
          gender: "other",
          avatar_key: student.avatar_key
        }
      }
    )

    expect(result).not_to be_success
    expect(result.row_errors[student.id.to_s]).to include(
      I18n.t("students.members.update_names.invalid_gender")
    )
    expect(student.reload.gender).to eq("boy")
  end

  it "allows inactive Students to share student numbers" do
    active_student = create_student(number: 1, active: true)
    inactive_student = create_student(number: 2, active: false)

    result = call_workflow(
      students: [inactive_student],
      rows: {
        inactive_student.id => {
          student_number: "1",
          name: inactive_student.name
        }
      }
    )

    expect(result).to be_success
    expect(active_student.reload.student_number).to eq(1)
    expect(inactive_student.reload.student_number).to eq(1)
  end

  it "converts a database unique conflict into a failed result" do
    first = create_student(number: 1)
    second = create_student(number: 2)
    allow_any_instance_of(Student).to receive(:save!)
      .and_raise(ActiveRecord::RecordNotUnique)

    result = call_workflow(
      students: [first, second],
      rows: {
        first.id => { student_number: "2", name: first.name },
        second.id => { student_number: "1", name: second.name }
      }
    )

    expect(result).not_to be_success
    expect(result.error_key).to eq(:failure)
    expect(result.row_errors.keys).to contain_exactly(first.id.to_s, second.id.to_s)
    expect([first, second].map { |student| student.reload.student_number }).to eq([1, 2])
  end

  it "preserves submitted raw values and row errors after validation fails" do
    student = create_student(number: 1)

    result = call_workflow(
      students: [student],
      rows: {
        student.id => {
          student_number: "abc",
          name: student.name,
          gender: "boy",
          avatar_key: "boy01"
        }
      }
    )

    expect(result).not_to be_success
    expect(result.rows[student.id.to_s]["student_number"]).to eq("abc")
    expect(result.row_errors[student.id.to_s]).to include(
      I18n.t("students.members.update_names.invalid_student_number")
    )
  end
end
