require "rails_helper"

RSpec.describe "Student growth dashboard", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:classroom) { create(:classroom) }
  let(:student) { create(:student, classroom:, name: "김학생", student_number: 7, student_pin: "1234") }
  let(:virtues) { classroom.virtues.active.in_display_order.to_a }

  around do |example|
    travel_to(Time.zone.local(2026, 9, 9, 12)) { example.run }
  end

  def sign_in_student
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id,
      student_pin: "1234"
    }
  end

  def create_record(date:, scores:, reflection: nil)
    configuration = classroom.daily_virtue_configurations.find_by(recorded_on: date)
    unless configuration
      configuration = classroom.daily_virtue_configurations.build(recorded_on: date)
      scores.each_key do |virtue|
        configuration.items.build(virtue:, name: virtue.name, position: virtue.position)
      end
    end
    record = student.daily_growth_records.build(
      classroom:, recorded_on: date, reflection:, daily_virtue_configuration: configuration
    )
    scores.each { |virtue, value| record.daily_growth_scores.build(virtue:, score: value) }
    record.save!
    record
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it "uses one wide Student dashboard and defaults an unrecorded Student to the today form" do
    other_student = create(:student, classroom:, name: "다른 학생")
    sign_in_student

    expect { get student_growth_path }.not_to change {
      [
        DailyVirtueConfiguration.count,
        DailyVirtueConfigurationItem.count,
        DailyGrowthRecord.count,
        DailyGrowthScore.count
      ]
    }

    dashboard = document.at_css("[data-growth-dashboard]")
    identity = document.at_css("[data-student-identity]")
    expect(dashboard["class"].split).to include("max-w-6xl")
    expect(identity.css("[data-student-identity-field]").map { |node| node["data-student-identity-field"] })
      .to eq(%w[school classroom name])
    expect(identity.text).to include(classroom.school_year.school.name, classroom.class_label, "7번", student.name)
    expect(identity.text).not_to include(other_student.name)
    expect(document.css("[data-student-teacher-action]")).to be_empty
    expect(document.at_css('[data-growth-tab="today"]')["aria-current"]).to eq("page")
    expect(document.at_css("[data-growth-today-form]")).to be_present
    expect(document.at_css('[data-growth-section="weekly"]')).to be_nil
  end

  it "shows an unassigned Student number in the shared identity" do
    student.update!(student_number: nil)
    sign_in_student

    get student_growth_path

    expect(document.at_css("[data-student-identity]").text)
      .to include(I18n.t("students.edit.self_pin.unassigned_student_number"))
  end

  it "shows a saved Student record as frozen-name score bars and allows explicit self-edit" do
    virtue = virtues.first
    frozen_name = virtue.name
    create_record(
      date: Time.zone.today,
      scores: { virtue => 3, virtues.second => 5 },
      reflection: "오늘의 성찰"
    )
    virtue.update!(name: "현재 덕목 이름", color_key: "rose")
    sign_in_student

    get student_growth_path(tab: "today")

    today = document.at_css("[data-today-growth-record]")
    expect(today.text).to include(
      frozen_name,
      I18n.t("daily_growth_records.score_value", score: 3),
      I18n.t("daily_growth_records.score_labels.3"),
      "오늘의 성찰"
    )
    expect(today.text).not_to include("현재 덕목 이름")
    bar = today.at_css(%([data-today-score="#{virtue.id}"] [data-score-bar]))
    expect(bar["style"]).to include("width: 60%", virtue.color_hex)
    expect(document.at_css("[data-growth-today-form]")).to be_nil

    get document.at_css("[data-edit-today-growth]")["href"]

    expect(response).to have_http_status(:ok)
    expect(document.at_css("[data-growth-today-form]")).to be_present
  end

  it "shows only the weekly chart when the Student selects growth" do
    create_record(
      date: Time.zone.today,
      scores: { virtues.first => 3, virtues.second => 5 }
    )
    sign_in_student

    get student_growth_path(tab: "growth", metric: virtues.first.id)

    expect(document.at_css('[data-growth-tab="growth"]')["aria-current"]).to eq("page")
    expect(document.at_css("[data-today-growth-record]")).to be_nil
    expect(document.at_css("[data-growth-today-form]")).to be_nil
    expect(document.at_css('[data-growth-section="weekly"]')).to be_present
    expect(document.at_css(%(svg[data-growth-metric="#{virtues.first.id}"]))).to be_present
    expect(document.at_css(%([data-graph-date="#{Time.zone.today.iso8601}"]))["data-growth-value"]).to eq("3")
  end

  it "shows one selected read-only surface at a time on the teacher dashboard" do
    teacher = create(:user, :teacher, :active_annual_teacher,
                     annual_school: classroom.school_year.school, annual_grade: classroom.grade)
    create(:homeroom_assignment, classroom:, teacher:)
    virtue = virtues.first
    frozen_name = virtue.name
    record = create_record(
      date: Time.zone.today,
      scores: { virtue => 3, virtues.second => 5 },
      reflection: "오늘의 성찰"
    )
    virtue.update!(name: "현재 덕목 이름", color_key: "rose")
    sign_in teacher

    get classroom_student_path(classroom, student)

    dashboard = document.at_css("[data-growth-dashboard]")
    identity = document.at_css("[data-student-identity]")
    expect(dashboard["class"].split).to include("max-w-6xl")
    expect(identity.css("[data-student-identity-field]").map { |node| node["data-student-identity-field"] })
      .to eq(%w[school classroom name])
    expect(identity.text).to include(classroom.school_year.school.name, classroom.class_label, "7번", student.name)
    expect(document.at_css('[data-student-teacher-action="back"]')).to be_present
    expect(document.at_css('[data-student-teacher-action="edit"]')).to be_present
    expect(document.at_css('[data-growth-tab="today"]')["aria-current"]).to eq("page")
    expect(document.at_css('[data-growth-section="weekly"]')).to be_nil
    today = document.at_css("[data-today-growth-record]")
    expect(today.text).to include(
      frozen_name,
      I18n.t("daily_growth_records.score_value", score: 3),
      I18n.t("daily_growth_records.score_labels.3"),
      "오늘의 성찰"
    )
    expect(today.text).not_to include("현재 덕목 이름")
    expect(document.css("form, input, textarea, button")).to be_empty

    get classroom_student_path(classroom, student, tab: "growth")

    expect(document.at_css('[data-growth-tab="growth"]')["aria-current"]).to eq("page")
    expect(document.at_css("[data-today-growth-record]")).to be_nil
    expect(document.at_css('[data-growth-section="weekly"]')).to be_present
    expect(document.css("form, input, textarea, button")).to be_empty
    expect(record.reload.daily_growth_scores.pluck(:score)).to match_array([3, 5])
  end
end
