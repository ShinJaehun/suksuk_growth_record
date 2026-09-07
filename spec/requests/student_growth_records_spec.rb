require "rails_helper"

RSpec.describe "Student daily growth records", type: :request do
  let(:classroom) { create(:classroom) }
  let(:student) { create(:student, classroom:, student_pin: "1234", name: "김학생") }

  def sign_in_student
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id,
      student_pin: "1234"
    }
  end

  def scores_for(virtues, value = 3)
    virtues.index_with { value }.transform_keys(&:id)
  end

  it "rejects access without a Student session" do
    get student_growth_record_path

    expect(response).to redirect_to(new_student_session_path)
  end

  it "shows the current active virtues to the signed-in Student" do
    sign_in_student

    get student_growth_record_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("오늘의 성장 기록", student.name)
    classroom.virtues.active.each { |virtue| expect(response.body).to include(virtue.name) }
  end

  it "creates today's record with every submitted score" do
    sign_in_student
    virtues = classroom.virtues.active.to_a

    post student_growth_record_path, params: {
      daily_growth_record: { scores: scores_for(virtues, 4), reflection: "오늘의 생각" }
    }

    record = student.daily_growth_records.find_by!(recorded_on: Time.zone.today)
    expect(response).to redirect_to(student_growth_record_path)
    expect(record.classroom).to eq(classroom)
    expect(record.reflection).to eq("오늘의 생각")
    expect(record.daily_growth_scores.pluck(:virtue_id, :score)).to match_array(
      virtues.map { |virtue| [virtue.id, 4] }
    )
  end

  it "allows a blank reflection" do
    sign_in_student

    post student_growth_record_path, params: {
      daily_growth_record: { scores: scores_for(classroom.virtues.active), reflection: "" }
    }

    expect(response).to redirect_to(student_growth_record_path)
    expect(student.daily_growth_records.find_by!(recorded_on: Time.zone.today).reflection).to eq("")
  end

  it "renders validation errors without creating a partial record" do
    sign_in_student
    virtues = classroom.virtues.active.to_a

    post student_growth_record_path, params: {
      daily_growth_record: { scores: scores_for(virtues.first(2)), reflection: "보존할 생각" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("모든 덕목의 점수를 확인해 주세요.", "보존할 생각")
    expect(student.daily_growth_records).to be_empty
  end

  it "ignores identity and date parameters" do
    other_student = create(:student)
    sign_in_student

    post student_growth_record_path, params: {
      daily_growth_record: {
        scores: scores_for(classroom.virtues.active),
        reflection: nil,
        student_id: other_student.id,
        classroom_id: other_student.classroom_id,
        recorded_on: Time.zone.tomorrow
      }
    }

    record = DailyGrowthRecord.last
    expect(record).to have_attributes(
      student_id: student.id,
      classroom_id: classroom.id,
      recorded_on: Time.zone.today
    )
  end

  it "shows today's stored scores and reflection" do
    record = DailyGrowthRecords::Save.call(
      student:,
      scores: scores_for(classroom.virtues.active, 4),
      reflection: "저장된 생각"
    )
    sign_in_student

    get student_growth_record_path

    document = Nokogiri::HTML(response.body)
    expect(response.body).to include("저장된 생각", "오늘 기록 수정")
    expect(response.body).to include(%(name="daily_growth_record[scores][#{record.daily_growth_scores.first.virtue_id}]"))
    expect(document.css('input[type="radio"][value="4"][checked="checked"]').size)
      .to eq(record.daily_growth_scores.size)
  end

  it "updates today's record" do
    virtues = classroom.virtues.active.to_a
    record = DailyGrowthRecords::Save.call(student:, scores: scores_for(virtues), reflection: nil)
    sign_in_student

    patch student_growth_record_path, params: {
      daily_growth_record: { scores: scores_for(virtues, 5), reflection: "수정됨" }
    }

    expect(response).to redirect_to(student_growth_record_path)
    expect(record.reload.reflection).to eq("수정됨")
    expect(record.daily_growth_scores.pluck(:score)).to all(eq(5))
  end

  it "keeps the captured virtues after another active virtue is added" do
    original_virtues = classroom.virtues.active.to_a
    record = DailyGrowthRecords::Save.call(student:, scores: scores_for(original_virtues))
    added_virtue = create(:virtue, classroom:, position: 4)
    sign_in_student

    get student_growth_record_path

    expect(response.body).not_to include(added_virtue.name)

    patch student_growth_record_path, params: {
      daily_growth_record: { scores: scores_for(original_virtues, 4), reflection: nil }
    }
    expect(record.reload.daily_growth_scores.map(&:virtue)).to match_array(original_virtues)
  end

  it "keeps and updates a captured virtue after it becomes inactive" do
    virtues = classroom.virtues.active.to_a
    record = DailyGrowthRecords::Save.call(student:, scores: scores_for(virtues))
    inactive_virtue = virtues.first
    inactive_virtue.update!(active: false)
    sign_in_student

    get student_growth_record_path
    expect(response.body).to include(inactive_virtue.name)

    patch student_growth_record_path, params: {
      daily_growth_record: { scores: scores_for(virtues, 5), reflection: nil }
    }
    expect(record.reload.daily_growth_scores.find_by!(virtue: inactive_virtue).score).to eq(5)
  end
end
