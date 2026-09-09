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
    expect(document.at_css('[data-growth-tab="growth"]')["aria-current"]).to eq("page")
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

    get student_growth_path(tab: "growth")

    today = document.at_css("[data-daily-growth-record]")
    expect(today.text).to include(
      frozen_name,
      I18n.t("daily_growth_records.score_value", score: 3),
      I18n.t("daily_growth_records.score_labels.3"),
      "오늘의 성찰"
    )
    expect(today.text).not_to include("현재 덕목 이름")
    bar = today.at_css(%([data-daily-score="#{virtue.id}"] [data-score-bar]))
    expect(bar["style"]).to include("width: 60%", virtue.color_hex)
    expect(document.at_css("[data-growth-today-form]")).to be_nil

    get document.at_css("[data-edit-today-growth]")["href"]

    expect(response).to have_http_status(:ok)
    expect(document.at_css("[data-growth-today-form]")).to be_present
  end

  it "shows only the weekly chart when the Student selects weekly" do
    create_record(
      date: Time.zone.today,
      scores: { virtues.first => 3, virtues.second => 5 }
    )
    sign_in_student

    get student_growth_path(tab: "weekly", metric: virtues.first.id)

    expect(document.at_css('[data-growth-tab="weekly"]')["aria-current"]).to eq("page")
    expect(document.at_css("[data-daily-growth-record]")).to be_nil
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
    expect(document.at_css('[data-growth-tab="growth"]')["aria-current"]).to eq("page")
    expect(document.at_css('[data-growth-section="weekly"]')).to be_nil
    today = document.at_css("[data-daily-growth-record]")
    expect(today.text).to include(
      frozen_name,
      I18n.t("daily_growth_records.score_value", score: 3),
      I18n.t("daily_growth_records.score_labels.3"),
      "오늘의 성찰"
    )
    expect(today.text).not_to include("현재 덕목 이름")
    expect(document.css("form, input, textarea, button")).to be_empty

    get classroom_student_path(classroom, student, tab: "weekly")

    expect(document.at_css('[data-growth-tab="weekly"]')["aria-current"]).to eq("page")
    expect(document.at_css("[data-daily-growth-record]")).to be_nil
    expect(document.at_css('[data-growth-section="weekly"]')).to be_present
    document.css('a[data-metric], a[data-week-navigation]').each do |link|
      expect(URI.parse(link["href"]).path).to eq(classroom_student_path(classroom, student))
      expect(Rack::Utils.parse_query(URI.parse(link["href"]).query)["tab"]).to eq("weekly")
    end
    expect(document.css("form, input, textarea, button")).to be_empty
    expect(record.reload.daily_growth_scores.pluck(:score)).to match_array([3, 5])
  end
  %w[student teacher manager admin].each do |actor_role|
    context "daily navigation as #{actor_role}" do
      let(:dashboard_path) do
        if actor_role == "student"
          student_growth_path
        else
          classroom_student_path(classroom, student)
        end
      end

      before do
        student
        case actor_role
        when "student"
          sign_in_student
        when "teacher"
          teacher = create(:user, :teacher, :active_annual_teacher,
                           annual_school: classroom.school_year.school, annual_grade: classroom.grade)
          create(:homeroom_assignment, classroom:, teacher:)
          sign_in teacher
        when "manager"
          sign_in create(:user, :teacher, :active_annual_teacher,
                         annual_school: classroom.school_year.school, annual_school_role: "manager")
        when "admin"
          sign_in create(:user, :admin)
        end
      end

      it "defaults missing, unsupported, and legacy tabs to daily growth" do
        [nil, "unknown", "today", "growth"].each do |tab|
          get dashboard_path, params: { tab: tab }

          expect(response).to have_http_status(:ok)
          expect(document.at_css('[data-growth-tab="growth"]')["aria-current"]).to eq("page")
          expect(document.at_css('[data-growth-date]')["data-growth-date"]).to eq("2026-09-09")
          expect(document.at_css('[data-growth-section="weekly"]')).to be_nil
        end
      end

      it "shows only a preparation state for monthly without creating rows" do
        expect { get dashboard_path, params: { tab: "monthly" } }.not_to change {
          [DailyVirtueConfiguration.count, DailyVirtueConfigurationItem.count,
           DailyGrowthRecord.count, DailyGrowthScore.count]
        }

        expect(response).to have_http_status(:ok)
        expect(document.at_css('[data-growth-section="monthly"]').text)
          .to include(I18n.t("student_app.navigation.coming_soon"))
        expect(document.css('[data-growth-date], [data-growth-section="weekly"], form')).to be_empty
      end

      it "reads past frozen scores and reflection without allowing edit mode" do
        virtue = virtues.first
        frozen_name = virtue.name
        record = create_record(date: Date.new(2026, 9, 8), scores: { virtue => 3 }, reflection: "과거 성찰")
        virtue.update!(name: "바뀐 이름", color_key: "rose")
        virtue.update!(active: false)

        get dashboard_path, params: { tab: "growth", date: "2026-09-08", edit: 1 }

        result = document.at_css('[data-daily-growth-record]')
        expect(result.text).to include(frozen_name, "과거 성찰",
                                      I18n.t("daily_growth_records.score_value", score: 3),
                                      I18n.t("daily_growth_records.score_labels.3"))
        expect(result.text).not_to include("바뀐 이름")
        expect(result.css('[data-daily-score]').size).to eq(1)
        expect(result.at_css('[data-score-bar]')["style"]).to include("width: 60%", virtue.color_hex)
        expect(document.css('form, [data-edit-today-growth]')).to be_empty
        expect(record.reload.daily_growth_scores.pluck(:score)).to eq([3])
        expect(record.reflection).to eq("과거 성찰")
      end

      it "keeps a missing past date empty even with an edit parameter" do
        expect { get dashboard_path, params: { tab: "growth", date: "2026-09-08", edit: 1 } }.not_to change {
          [DailyVirtueConfiguration.count, DailyVirtueConfigurationItem.count,
           DailyGrowthRecord.count, DailyGrowthScore.count]
        }

        expect(document.at_css('[data-growth-date]')["data-growth-date"]).to eq("2026-09-08")
        expect(document.at_css('[data-daily-growth-record]').text).to include(I18n.t("student_growth.no_data"))
        expect(document.css('form, [data-score-bar], [data-edit-today-growth]')).to be_empty
      end

      it "falls back to an unrecorded today without writing rows for invalid or future dates" do
        [nil, "", "invalid", "2026-02-30", "2026-09-10", ["2026-09-08"]].each do |date|
          expect { get dashboard_path, params: { tab: "growth", date: date } }.not_to change {
            [DailyVirtueConfiguration.count, DailyVirtueConfigurationItem.count,
             DailyGrowthRecord.count, DailyGrowthScore.count]
          }

          expect(response).to have_http_status(:ok)
          expect(document.at_css('[data-growth-date]')["data-growth-date"]).to eq("2026-09-09")
          if actor_role == "student"
            expect(document.at_css('[data-growth-today-form]')).to be_present
          else
            expect(document.css('form, [data-edit-today-growth]')).to be_empty
            expect(document.at_css('[data-daily-growth-record]').text)
              .to include(I18n.t("teacher_growth_records.not_completed"))
          end
        end
      end

      it "uses today's saved result for explicit today and fallback dates" do
        create_record(date: Time.zone.today, scores: { virtues.first => 4 }, reflection: "오늘 기록")
        create_record(date: Time.zone.tomorrow, scores: { virtues.first => 5 }, reflection: "미래 기록")

        ["2026-09-09", "invalid", "2026-09-10"].each do |date|
          get dashboard_path, params: { tab: "growth", date: date }

          expect(document.at_css('[data-growth-date]')["data-growth-date"]).to eq("2026-09-09")
          expect(document.at_css('[data-daily-growth-record]').text).to include("오늘 기록")
          expect(response.body).not_to include("미래 기록")
          expect(document.at_css('[data-record-navigation="next"]')).to be_nil
          expect(document.at_css('[data-edit-today-growth]').present?).to eq(actor_role == "student")
          expect(document.css('form')).to be_empty
        end
      end

      it "navigates actual records including weekends, excluding other Students and future records" do
        [4, 5, 8, 9, 10].each do |day|
          create_record(date: Date.new(2026, 9, day), scores: { virtues.first => 3 })
        end
        other_student = create(:student, classroom:)
        create(:daily_growth_record, :with_score, student: other_student, recorded_on: Date.new(2026, 9, 7))

        get dashboard_path, params: { tab: "growth", date: "2026-09-08", student_id: other_student.id }

        previous_path = document.at_css('[data-record-navigation="previous"]')["href"]
        next_path = document.at_css('[data-record-navigation="next"]')["href"]
        expect(URI.parse(previous_path).path).to eq(dashboard_path)
        expect(Rack::Utils.parse_query(URI.parse(previous_path).query))
          .to eq("tab" => "growth", "date" => "2026-09-05")
        expect(URI.parse(next_path).path).to eq(dashboard_path)
        expect(Rack::Utils.parse_query(URI.parse(next_path).query))
          .to eq("tab" => "growth", "date" => "2026-09-09")

        get next_path

        expect(document.at_css('[data-record-navigation="next"]')).to be_nil
        get dashboard_path, params: { tab: "growth", date: "2026-09-04" }
        expect(document.at_css('[data-record-navigation="previous"]')).to be_nil
      end

      it "returns to an unrecorded today through growth navigation without a separate today action" do
        create_record(date: Date.new(2026, 9, 8), scores: { virtues.first => 3 })
        get dashboard_path, params: { tab: "growth", date: "2026-09-08" }

        expect(document.at_css('[data-record-navigation="next"]')).to be_nil
        growth_link = document.at_css('[data-growth-tab="growth"]')
        expect(growth_link["href"]).to eq("#{dashboard_path}?tab=growth")
        expect(document.css('[data-growth-tab="today"]')).to be_empty

        get growth_link["href"]

        expect(document.at_css('[data-growth-date]')["data-growth-date"]).to eq("2026-09-09")
        previous_path = document.at_css('[data-record-navigation="previous"]')["href"]
        expect(URI.parse(previous_path).path).to eq(dashboard_path)
        expect(Rack::Utils.parse_query(URI.parse(previous_path).query))
          .to eq("tab" => "growth", "date" => "2026-09-08")
        if actor_role == "student"
          expect(document.at_css('[data-growth-today-form]')).to be_present
        else
          expect(document.css('form')).to be_empty
          expect(document.at_css('[data-daily-growth-record]').text)
            .to include(I18n.t("teacher_growth_records.not_completed"))
        end
      end
    end
  end
end
