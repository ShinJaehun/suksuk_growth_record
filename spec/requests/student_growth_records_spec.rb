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

  it "redirects the legacy signed-in GET to the canonical today dashboard" do
    sign_in_student

    get student_growth_record_path

    expect(response).to redirect_to(student_growth_path(tab: "growth"))
  end

  it "shows the current active virtues to the signed-in Student" do
    sign_in_student

    get student_growth_path(tab: "growth")

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
    expect(response).to redirect_to(student_growth_path(tab: "growth"))
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

    expect(response).to redirect_to(student_growth_path(tab: "growth"))
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
    renamed_virtue = record.daily_growth_scores.first.virtue
    original_name = renamed_virtue.name
    renamed_virtue.update!(name: "책 읽기")
    sign_in_student

    get student_growth_path(tab: "growth", edit: 1)

    document = Nokogiri::HTML(response.body)
    expect(response.body).to include("저장된 생각", "오늘 기록 수정")
    expect(response.body).to include(%(name="daily_growth_record[scores][#{record.daily_growth_scores.first.virtue_id}]"))
    expect(document.css('input[type="radio"][value="4"][checked="checked"]').size)
      .to eq(record.daily_growth_scores.size)
    expect(document.css("legend").map(&:text)).to include(original_name)
    expect(document.css("legend").map(&:text)).not_to include(renamed_virtue.name)
  end

  it "updates today's record" do
    virtues = classroom.virtues.active.to_a
    record = DailyGrowthRecords::Save.call(student:, scores: scores_for(virtues), reflection: nil)
    original_scores = record.daily_growth_scores.pluck(:id, :virtue_id)
    configuration = record.daily_virtue_configuration
    original_items = configuration.items.pluck(:virtue_id, :name)
    virtues.first.update!(name: "책 읽기")
    sign_in_student

    patch student_growth_record_path, params: {
      daily_growth_record: { scores: scores_for(virtues, 5), reflection: "수정됨" }
    }

    expect(response).to redirect_to(student_growth_path(tab: "growth"))
    expect(record.reload.reflection).to eq("수정됨")
    expect(record.daily_growth_scores.pluck(:score)).to all(eq(5))
    expect(record.daily_growth_scores.pluck(:id, :virtue_id)).to match_array(original_scores)
    expect(record.daily_virtue_configuration).to eq(configuration)
    expect(configuration.reload.items.pluck(:virtue_id, :name)).to eq(original_items)
    follow_redirect!
    expect(response.body).to include("독서", "수정됨")
    expect(response.body).not_to include("책 읽기")
    expect(Nokogiri::HTML(response.body).css("form")).to be_empty
  end

  it "keeps past records unchanged when date and record parameters target history" do
    past_record = create(:daily_growth_record, :with_score, student:, recorded_on: Time.zone.yesterday,
                         reflection: "과거 성찰")
    past_scores = past_record.daily_growth_scores.pluck(:id, :score)
    virtues = classroom.virtues.active.to_a
    today_record = DailyGrowthRecords::Save.call(student:, scores: scores_for(virtues))
    sign_in_student

    [Time.zone.yesterday, Time.zone.tomorrow].each do |date|
      patch student_growth_record_path, params: {
        date: date.iso8601,
        id: past_record.id,
        daily_growth_record: {
          recorded_on: date.iso8601,
          scores: scores_for(virtues, 5),
          reflection: "오늘만 수정"
        }
      }

      expect(response).to redirect_to(student_growth_path(tab: "growth"))
      expect(past_record.reload.reflection).to eq("과거 성찰")
      expect(past_record.daily_growth_scores.pluck(:id, :score)).to eq(past_scores)
      expect(today_record.reload.reflection).to eq("오늘만 수정")
      expect(today_record.daily_growth_scores.pluck(:score)).to all(eq(5))
      expect(student.daily_growth_records.pluck(:recorded_on))
        .to match_array([Time.zone.yesterday, Time.zone.today])
    end
  end

  it "keeps snapshot labels when an update fails after a teacher rename" do
    virtues = classroom.virtues.active.to_a
    record = DailyGrowthRecords::Save.call(student:, scores: scores_for(virtues))
    original_scores = record.daily_growth_scores.pluck(:id, :virtue_id)
    configuration = record.daily_virtue_configuration
    original_items = configuration.items.pluck(:virtue_id, :name)
    virtues.first.update!(name: "책 읽기")
    sign_in_student

    patch student_growth_record_path, params: {
      daily_growth_record: { scores: scores_for(virtues.first(2)), reflection: "보존할 생각" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    labels = Nokogiri::HTML(response.body).css("legend").map(&:text)
    expect(labels).to include("독서")
    expect(labels).not_to include("책 읽기")
    expect(response.body).to include("보존할 생각")
    expect(record.reload.daily_growth_scores.pluck(:id, :virtue_id)).to match_array(original_scores)
    expect(configuration.reload.items.pluck(:virtue_id, :name)).to eq(original_items)
  end

  it "keeps the captured virtues after another active virtue is added" do
    original_virtues = classroom.virtues.active.to_a
    record = DailyGrowthRecords::Save.call(student:, scores: scores_for(original_virtues))
    added_virtue = create(:virtue, classroom:, position: 4)
    sign_in_student

    get student_growth_path(tab: "growth", edit: 1)

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

    get student_growth_path(tab: "growth", edit: 1)
    expect(response.body).to include(inactive_virtue.name)

    patch student_growth_record_path, params: {
      daily_growth_record: { scores: scores_for(virtues, 5), reflection: nil }
    }
    expect(record.reload.daily_growth_scores.find_by!(virtue: inactive_virtue).score).to eq(5)
  end

  it "previews current virtues without creating a configuration on GET" do
    sign_in_student

    expect { get student_growth_path(tab: "growth") }.not_to change {
      [DailyVirtueConfiguration.count, DailyVirtueConfigurationItem.count, DailyGrowthRecord.count]
    }

    expect(response).to have_http_status(:ok)
  end

  it "shows and saves the frozen configuration for a Student who has not recorded yet" do
    virtues = classroom.virtues.active.to_a
    first_student = create(:student, classroom:)
    first_record = DailyGrowthRecords::Save.call(student: first_student, scores: scores_for(virtues))
    old_names = first_record.daily_virtue_configuration.items.map(&:name)
    virtues.first.update!(name: "책 읽기")
    virtues.last.update!(active: false)
    added_virtue = create(:virtue, classroom:)
    sign_in_student

    get student_growth_path(tab: "growth")

    expect(Nokogiri::HTML(response.body).css("legend").map(&:text)).to eq(old_names)
    expect(response.body).not_to include(added_virtue.name, "책 읽기")
    post student_growth_record_path, params: {
      daily_growth_record: { scores: scores_for(virtues, 4), reflection: "늦게 입력한 생각" }
    }

    expect(response).to redirect_to(student_growth_path(tab: "growth"))
    record = student.daily_growth_records.find_by!(recorded_on: Time.zone.today)
    expect(record.daily_virtue_configuration).to eq(first_record.daily_virtue_configuration)
    expect(record.daily_growth_scores.map(&:virtue)).to match_array(virtues)
  end

  it "rejects a stale preview without freezing or rewriting the submitted scores" do
    virtues = classroom.virtues.active.to_a
    sign_in_student
    get student_growth_path(tab: "growth")
    added_virtue = create(:virtue, classroom:)

    expect do
      post student_growth_record_path, params: {
        daily_growth_record: { scores: scores_for(virtues), reflection: "보존할 생각" }
      }
    end.not_to change {
      [DailyVirtueConfiguration.count, DailyVirtueConfigurationItem.count, DailyGrowthRecord.count, DailyGrowthScore.count]
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(added_virtue.name, "보존할 생각", "모든 덕목의 점수를 확인해 주세요.")
  end
end
