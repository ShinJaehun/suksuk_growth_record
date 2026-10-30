require "rails_helper"

RSpec.describe "Monthly growth calendar", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:classroom) { create(:classroom) }
  let(:student) { create(:student, classroom: classroom, student_pin: "1234") }
  let(:virtues) { classroom.virtues.active.in_display_order.to_a }

  around do |example|
    travel_to(Time.zone.local(2026, 3, 11, 12)) { example.run }
  end

  before do
    allow(PublicHolidays::Calendar).to receive(:for_year).and_return([
      { date: Date.new(2026, 3, 1), name: "삼일절" },
      { date: Date.new(2026, 3, 2), name: "대체공휴일" }
    ])
  end

  def sign_in_student
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id, student_pin: "1234"
    }
  end

  def create_record(date:, scores:, owner: student)
    configuration = owner.classroom.daily_virtue_configurations.find_by(recorded_on: date)
    unless configuration
      configuration = owner.classroom.daily_virtue_configurations.build(recorded_on: date)
      scores.each_key do |virtue|
        configuration.items.build(virtue: virtue, name: virtue.name, position: virtue.position)
      end
    end
    record = owner.daily_growth_records.build(
      classroom: owner.classroom, recorded_on: date, daily_virtue_configuration: configuration
    )
    scores.each { |virtue, value| record.daily_growth_scores.build(virtue: virtue, score: value) }
    record.save!
    record
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def day(date)
    document.at_css(%([data-calendar-date="#{date}"]))
  end

  def query(link)
    Rack::Utils.parse_query(URI.parse(link["href"]).query)
  end

  it "requires a Student session" do
    get student_growth_path, params: { tab: "monthly" }

    expect(response).to redirect_to(new_student_session_path)
  end

  it "renders one arithmetic-mean bubble per recorded day including weekends and holidays" do
    create_record(date: Date.new(2026, 3, 2), scores: { virtues.first => 1, virtues.second => 4 })
    create_record(date: Date.new(2026, 3, 7), scores: { virtues.first => 5, virtues.second => 4 })
    create_record(date: Date.new(2026, 3, 8), scores: { virtues.first => 3 })
    sign_in_student

    get student_growth_path, params: { tab: "monthly" }

    expect(response).to have_http_status(:ok)
    expect(document.at_css('[data-calendar-month]')["data-calendar-month"]).to eq("2026-03")
    expect(document.css('[data-calendar-date]').first["data-calendar-date"]).to eq("2026-03-01")
    expect(day("2026-03-31")).to be_present
    expect(document.css('[data-calendar-date] circle').size).to eq(3)
    expect(day("2026-03-02")["data-growth-value"].to_f).to eq(2.5)
    expect(day("2026-03-02")["aria-label"])
      .to include("2026.03.02", I18n.t("student_growth.score", value: "2.5"))
    expect(day("2026-03-02").at_css('.growth-calendar__date').text).to eq("2")
    expect(day("2026-03-02").text).not_to include(I18n.t("student_growth.score", value: "2.5"))
    expect(document.at_css('[data-growth-section="monthly"]').text)
      .not_to include("1~5점", "점수가 높을수록", "일일 기록을 볼 수 있어요")
    expect(day("2026-03-02").text).to include("대체공휴일")
    expect(day("2026-03-02")["class"]).to include("growth-calendar__day--public-holiday")
    expect(day("2026-03-07")["class"]).to include("growth-calendar__day--saturday")
    expect(day("2026-03-08")["class"]).to include("growth-calendar__day--sunday")
    %w[2026-03-02 2026-03-07 2026-03-08].each do |date|
      expect(day(date).name).to eq("div")
      expect(day(date)["href"]).to be_nil
    end
    expect(day("2026-03-07").at_css("circle")["r"].to_f)
      .to be > day("2026-03-02").at_css("circle")["r"].to_f
    expect(day("2026-03-02").at_css("circle")["fill"]).to eq(StudentGrowthHelper::OVERALL_GROWTH_COLOR)
    expect(document.css('[data-growth-section="weekly"], [data-daily-growth-record], form')).to be_empty
  end

  it "distinguishes missing records, missing selected scores, low scores, and future days" do
    create_record(date: Date.new(2026, 3, 2), scores: { virtues.first => 1 })
    create_record(date: Date.new(2026, 3, 3), scores: { virtues.second => 5 })
    create_record(date: Date.new(2026, 3, 4), scores: { virtues.first => 1 })
    create_record(date: Date.new(2026, 3, 12), scores: { virtues.first => 5 })
    sign_in_student

    get student_growth_path, params: { tab: "monthly", metric: virtues.first.id }

    expect(day("2026-03-01")["data-calendar-state"]).to eq("no_record")
    expect(day("2026-03-03")["data-calendar-state"]).to eq("no_score")
    expect(day("2026-03-12")["data-calendar-state"]).to eq("future")
    %w[2026-03-01 2026-03-03 2026-03-12].each do |date|
      expect(day(date).css("circle")).to be_empty
    end
    expect(day("2026-03-02").css("circle").size).to eq(1)
    expect(day("2026-03-02").at_css("circle")["fill"]).to eq(virtues.first.color_hex)
    %w[2026-03-03 2026-03-04].each do |date|
      expect(day(date).name).to eq("a")
      expect(query(day(date))).to eq("tab" => "growth", "date" => date)
      expect(URI.parse(day(date)["href"]).path).to eq(student_growth_path)
    end
    %w[2026-03-01 2026-03-02 2026-03-11 2026-03-12 2026-04-01].each do |date|
      expect(day(date).name).to eq("div")
      expect(day(date)["href"]).to be_nil
    end
    expect(day("2026-03-05").text.strip).to eq("5")
    expect(day("2026-03-05").to_html).not_to include("입력 없음", I18n.t("student_growth.monthly.no_record"))
  end

  it "keeps month and metric in their navigation links and prevents future-month navigation" do
    sign_in_student
    get student_growth_path, params: { tab: "monthly", month: "2026-02", metric: virtues.first.id }

    expect(document.at_css('[data-growth-section="monthly"]')["data-growth-metric"]).to eq(virtues.first.id.to_s)
    document.css('a[data-metric]').each do |link|
      expect(query(link)).to include("tab" => "monthly", "month" => "2026-02")
    end
    expect(query(document.at_css('[data-month-navigation="previous"]')))
      .to eq("tab" => "monthly", "month" => "2026-01", "metric" => virtues.first.id.to_s)
    next_link = document.at_css('[data-month-navigation="next"]')
    expect(query(next_link)).to eq("tab" => "monthly", "month" => "2026-03", "metric" => virtues.first.id.to_s)

    get next_link["href"]

    expect(document.at_css('[data-growth-section="monthly"]')["data-growth-metric"]).to eq(virtues.first.id.to_s)
    expect(document.at_css('[data-month-navigation="next"]')).to be_nil
  end

  it "uses the current month for malformed or future month parameters without writing domain rows" do
    sign_in_student
    [nil, "", "invalid", "2026-13", "2026-04", ["2026-02"]].each do |month|
      expect { get student_growth_path, params: { tab: "monthly", month: month } }.not_to change {
        [DailyVirtueConfiguration.count, DailyVirtueConfigurationItem.count, DailyGrowthRecord.count, DailyGrowthScore.count]
      }
      expect(response).to have_http_status(:ok)
      expect(document.at_css('[data-calendar-month]')["data-calendar-month"]).to eq("2026-03")
    end
  end

  it "offers scored inactive virtues using current identity and color without changing frozen configuration" do
    virtue = virtues.first
    record = create_record(date: Date.new(2026, 3, 2), scores: { virtue => 4 })
    frozen_name = record.daily_virtue_configuration.items.first.name
    virtue.update!(active: false, name: "현재 이름", color_key: "rose")
    inactive_unscored = create(:virtue, classroom: classroom, active: false)
    sign_in_student

    get student_growth_path, params: { tab: "monthly", metric: virtue.id }

    expect(document.at_css(%([data-metric="#{virtue.id}"]))["aria-current"]).to eq("true")
    expect(document.at_css(%([data-metric="#{virtue.id}"])).text).to include("현재 이름")
    expect(day("2026-03-02").at_css("circle")["fill"]).to eq(virtue.color_hex)
    expect(document.at_css(%([data-metric="#{inactive_unscored.id}"]))).to be_nil
    expect(record.daily_virtue_configuration.items.first.reload.name).to eq(frozen_name)
  end

  it "ignores another Student's records and foreign or unknown metrics" do
    other_student = create(:student, classroom: classroom)
    create_record(date: Date.new(2026, 3, 2), scores: { virtues.first => 5 }, owner: other_student)
    foreign_virtue = create(:virtue)
    sign_in_student

    [foreign_virtue.id, "unknown"].each do |metric|
      get student_growth_path, params: { tab: "monthly", student_id: other_student.id, metric: metric }

      expect(document.at_css('[data-growth-section="monthly"]')["data-growth-metric"]).to eq("overall")
      expect(document.css('[data-calendar-date] circle')).to be_empty
      expect(day("2026-03-02")["data-calendar-state"]).to eq("no_record")
    end
  end

  it "retains a scored inactive metric across months with no records" do
    virtue = virtues.first
    create_record(date: Date.new(2026, 3, 2), scores: { virtue => 4 })
    virtue.update!(active: false)
    sign_in_student

    get student_growth_path, params: { tab: "monthly", month: "2026-02", metric: virtue.id }

    expect(document.at_css('[data-growth-section="monthly"]')["data-growth-metric"]).to eq(virtue.id.to_s)
    expect(document.at_css(%([data-metric="#{virtue.id}"]))["aria-current"]).to eq("true")
    expect(document.css('[data-calendar-date] circle')).to be_empty
    next_link = document.at_css('[data-month-navigation="next"]')
    expect(query(next_link)["metric"]).to eq(virtue.id.to_s)

    get next_link["href"]

    expect(day("2026-03-02")["data-growth-value"].to_f).to eq(4)
  end

  it "keeps the calendar available and reports unavailable holiday data" do
    allow(PublicHolidays::Calendar).to receive(:for_year).and_return(nil)
    create_record(date: Date.new(2026, 3, 3), scores: { virtues.first => 4 })
    sign_in_student

    get student_growth_path, params: { tab: "monthly" }

    expect(response).to have_http_status(:ok)
    expect(document.at_css('[data-growth-section="monthly"]').text)
      .to include(I18n.t("student_growth.monthly.holidays_unavailable"))
    expect(day("2026-03-11")).to be_present
    expect(day("2026-03-03").css("circle").size).to eq(1)
    expect(document.css('a[data-calendar-date]')).to be_empty
  end

  %w[teacher manager admin].each do |role|
    it "shows the same read-only scores and scoped links for #{role}" do
      record = create_record(date: Date.new(2026, 3, 3), scores: { virtues.first => 4 })
      [2, 7, 8].each do |date|
        create_record(date: Date.new(2026, 3, date), scores: { virtues.first => 4 })
      end
      actor = if role == "admin"
        create(:user, :admin)
      else
        create(:user, :teacher, :active_annual_teacher,
          annual_school: classroom.school_year.school, annual_grade: classroom.grade,
          annual_school_role: role == "manager" ? "manager" : "member")
      end
      create(:homeroom_assignment, classroom: classroom, teacher: actor) if role == "teacher"
      sign_in actor
      path = classroom_student_path(classroom, student)

      expect { get path, params: { tab: "monthly", metric: virtues.first.id, date: "2026-03-03" } }.not_to change {
        [DailyVirtueConfiguration.count, DailyVirtueConfigurationItem.count, DailyGrowthRecord.count, DailyGrowthScore.count]
      }

      expect(response).to have_http_status(:ok)
      expect(day("2026-03-03")["data-growth-value"].to_f).to eq(4)
      expect(day("2026-03-03").at_css("circle")["r"].to_f).to eq(33)
      expect(day("2026-03-03")["aria-label"])
        .to include("2026.03.03", I18n.t("student_growth.score", value: "4"))
      expect(day("2026-03-03").text.strip).to eq("3")
      expect(query(day("2026-03-03"))).to eq("tab" => "monthly", "month" => "2026-03", "metric" => virtues.first.id.to_s, "date" => "2026-03-03")
      %w[2026-03-02 2026-03-07 2026-03-08].each do |date|
        expect(day(date).name).to eq("div")
        expect(day(date)["href"]).to be_nil
      end
      expect(day("2026-03-04").text.strip).to eq("4")
      expect(day("2026-03-04").to_html).not_to include("입력 없음", I18n.t("student_growth.monthly.no_record"))
      document.css('a[data-metric], a[data-month-navigation], a[data-calendar-date]').each do |link|
        expect(URI.parse(link["href"]).path).to eq(path)
      end
      expect(document.css('form, input, textarea, button, [data-edit-today-growth]')).to be_empty
      expect(record.reload.daily_growth_scores.pluck(:score)).to eq([4])

      expect(day("2026-03-03")["aria-current"]).to eq("date")
      empty_path = day("2026-03-04")["href"]
      expect { get empty_path }.not_to change {
        [DailyVirtueConfiguration.count, DailyGrowthRecord.count, DailyGrowthScore.count,
         record.reload.attributes, record.daily_growth_scores.map(&:attributes)]
      }
      expect(document.at_css('[data-daily-growth-record]').text.strip)
        .to eq(I18n.t("student_growth.empty_past_record"))
      expect(document.css('[data-score-bar], form, [data-edit-today-growth]')).to be_empty
      expect(document.at_css('[data-calendar-month]')["data-calendar-month"]).to eq("2026-03")
      expect(day("2026-03-04")["aria-current"]).to eq("date")

      get document.at_css('[data-month-navigation="previous"]')["href"]
      expect(document.at_css('[data-growth-date]')["data-growth-date"]).to eq("2026-03-04")
      expect(document.at_css('[data-calendar-month]')["data-calendar-month"]).to eq("2026-02")
      expect(document.at_css('[data-growth-section="monthly"]')["data-growth-metric"]).to eq(virtues.first.id.to_s)
      get document.at_css('[data-month-navigation="next"]')["href"]

      get day("2026-03-03")["href"]
      expect(document.at_css('[data-daily-growth-record]').text)
        .to include(I18n.t("daily_growth_records.score_value", score: 4))
      expect(document.at_css('[data-growth-section="monthly"]')).to be_present
      expect(document.css('form, [data-edit-today-growth]')).to be_empty
    end
  end

  it "rejects an unrelated teacher, a different school's manager, and a Student outside the URL classroom" do
    student
    outsider = create(:user, :teacher, :active_annual_teacher, annual_school: classroom.school_year.school)
    foreign_manager = create(:user, :teacher, :active_annual_teacher,
      annual_school: create(:school), annual_school_role: "manager")
    [outsider, foreign_manager].each do |actor|
      sign_in actor
      get classroom_student_path(classroom, student), params: { tab: "monthly" }
      expect(response).to redirect_to(root_path)
      expect(document.css('[data-growth-section="monthly"]')).to be_empty
      sign_out actor
    end

    sign_in create(:user, :admin)
    get classroom_student_path(create(:classroom), student), params: { tab: "monthly" }
    expect(response).to have_http_status(:not_found)
  end

  it "keeps inactive classroom growth inaccessible" do
    student
    classroom.update!(active: false)
    sign_in create(:user, :admin)

    get classroom_student_path(classroom, student), params: { tab: "monthly" }

    expect(response).to redirect_to(root_path)
    expect(document.css('[data-growth-section="monthly"]')).to be_empty
  end
end
