require "rails_helper"

RSpec.describe "Student weekly growth", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:classroom) { create(:classroom) }
  let(:student) { create(:student, classroom:, student_pin: "1234") }
  let(:virtues) { classroom.virtues.active.in_display_order.to_a }
  let(:monday) { Date.new(2026, 9, 7) }

  around do |example|
    travel_to(Time.zone.local(2026, 9, 9, 12)) { example.run }
  end

  def sign_in_student
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id,
      student_pin: "1234"
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
    scores.each { |virtue, value| record.daily_growth_scores.build(virtue:, score: value) }
    record.save!
    record
  end

  def document
    Nokogiri::HTML(response.body)
  end

  def graph_day(date)
    document.at_css(%([data-graph-date="#{date.iso8601}"]))
  end

  def graph_metric
    document.at_css("svg[data-growth-metric]")["data-growth-metric"]
  end

  it "rejects access without a Student session" do
    get student_growth_path, params: { tab: "weekly" }

    expect(response).to redirect_to(new_student_session_path)
  end

  it "rejects a Student whose classroom became inactive" do
    sign_in_student
    classroom.update!(active: false)

    get student_growth_path, params: { tab: "weekly" }

    expect(response).to redirect_to(public_student_login_path(student_login_token: classroom.student_login_token))
  end

  it "defaults to overall and presents the current Monday through Friday" do
    sign_in_student

    get student_growth_path, params: { tab: "weekly" }

    expect(response).to have_http_status(:ok)
    expect(graph_metric).to eq("overall")
    document.css('a[data-metric], a[data-week-navigation]').each do |link|
      expect(Rack::Utils.parse_query(URI.parse(link["href"]).query)["tab"]).to eq("weekly")
    end
    expect(document.at_css('[data-metric="overall"]')["aria-current"]).to eq("true")
    expect(document.at_css("[data-week-start]")["data-week-start"]).to eq("2026-09-07")
    expect(document.at_css("[data-week-end]")["data-week-end"]).to eq("2026-09-11")
    expect(document.css("[data-graph-date]").map { |day| day["data-graph-date"] })
      .to eq((monday..monday + 4).map(&:iso8601))
  end

  it "uses the application date when UTC is still Sunday" do
    travel_to(Time.zone.local(2026, 9, 7, 0, 30))
    sign_in_student

    get student_growth_path, params: { tab: "weekly" }

    expect(document.at_css("[data-week-start]")["data-week-start"]).to eq("2026-09-07")
  end

  it "reads only the signed-in Student's data despite identity parameters" do
    other_student = create(:student, classroom:)
    create_record(date: monday, scores: { virtues.first => 2 })
    create_record(date: monday, scores: { virtues.first => 5 }, owner: other_student)
    create_record(date: monday + 1, scores: { virtues.first => 5 }, owner: other_student)
    sign_in_student

    get student_growth_path, params: { tab: "weekly", student_id: other_student.id, classroom_id: classroom.id }

    expect(graph_day(monday)["data-growth-value"].to_f).to eq(40.0)
    expect(graph_day(monday + 1)["data-growth-value"]).to eq("")
    expect(graph_day(monday + 1).css("circle")).to be_empty
  end

  it "displays the average of actual scores as a percentage without changing stored scores" do
    record = create_record(date: monday, scores: { virtues[0] => 3, virtues[1] => 5 })
    sign_in_student

    get student_growth_path, params: { tab: "weekly" }

    expect(graph_day(monday)["data-growth-value"].to_f).to eq(80.0)
    expect(graph_day(monday).css("circle").size).to eq(1)
    expect(document.css("[data-y-axis-tick]").map { |tick| tick["data-y-axis-tick"].to_i })
      .to eq([100, 80, 60, 40, 20, 0])
    expect(record.reload.daily_growth_scores.pluck(:score)).to match_array([3, 5])
    expect(record.average_score).to eq(4.0)
  end

  it "displays an individual virtue's actual score on the zero to five axis" do
    create_record(date: monday, scores: { virtues[0] => 1, virtues[1] => 5 })
    sign_in_student

    get student_growth_path, params: { tab: "weekly", metric: virtues[0].id }

    expect(graph_metric).to eq(virtues[0].id.to_s)
    expect(graph_day(monday)["data-growth-value"]).to eq("1")
    expect(graph_day(monday).css("circle").size).to eq(1)
    expect(document.css("[data-y-axis-tick]").map { |tick| tick["data-y-axis-tick"].to_i })
      .to eq([5, 4, 3, 2, 1, 0])
  end

  it "keeps missing dates empty without points, lines, or fake database rows" do
    sign_in_student

    expect { get student_growth_path, params: { tab: "weekly" } }.not_to change {
      [DailyGrowthRecord.count, DailyGrowthScore.count]
    }

    expect(document.css("[data-graph-date]").map { |day| day["data-growth-value"] })
      .to eq(Array.new(5, ""))
    expect(document.css("svg circle, svg path")).to be_empty
  end

  it "keeps a missing virtue score empty even when the date has another score" do
    create_record(date: monday, scores: { virtues[1] => 5 })
    sign_in_student

    get student_growth_path, params: { tab: "weekly", metric: virtues[0].id }

    expect(graph_day(monday)["data-growth-value"]).to eq("")
    expect(graph_day(monday).css("circle")).to be_empty
    expect(document.css("svg path")).to be_empty
  end

  it "does not connect scores across a missing day" do
    create_record(date: monday, scores: { virtues[0] => 3 })
    create_record(date: monday + 2, scores: { virtues[0] => 5 })
    sign_in_student

    get student_growth_path, params: { tab: "weekly" }

    expect(document.css("svg circle").size).to eq(2)
    expect(document.css("svg path")).to be_empty
  end

  it "draws a line with round caps and joins for consecutive scores" do
    create_record(date: monday, scores: { virtues[0] => 3 })
    create_record(date: monday + 1, scores: { virtues[0] => 5 })
    sign_in_student

    get student_growth_path, params: { tab: "weekly" }

    expect(document.css("svg path").size).to eq(1)
    expect(document.at_css("svg path")["stroke-linecap"]).to eq("round")
    expect(document.at_css("svg path")["stroke-linejoin"]).to eq("round")
  end

  it "loads the previous week's records through Friday and excludes the current week" do
    create_record(date: monday - 3, scores: { virtues[0] => 5 })
    create_record(date: monday, scores: { virtues[0] => 1 })
    sign_in_student
    get student_growth_path, params: { tab: "weekly" }

    get document.at_css('[data-week-navigation="previous"]')["href"]

    expect(document.at_css("[data-week-start]")["data-week-start"]).to eq("2026-08-31")
    expect(document.at_css("[data-week-end]")["data-week-end"]).to eq("2026-09-04")
    expect(graph_day(monday - 3)["data-growth-value"].to_f).to eq(100.0)
    expect(graph_day(monday)).to be_nil
  end

  it "excludes stored weekend records from presentation and inactive metric discovery" do
    travel_to(Time.zone.local(2026, 9, 13, 12))
    virtue = virtues[0]
    create_record(date: monday + 5, scores: { virtue => 4 })
    create_record(date: monday + 6, scores: { virtue => 5 })
    virtue.update!(active: false)
    sign_in_student

    get student_growth_path, params: { tab: "weekly", metric: virtue.id }

    expect(document.at_css("[data-week-start]")["data-week-start"]).to eq("2026-09-07")
    expect(document.at_css("[data-week-end]")["data-week-end"]).to eq("2026-09-11")
    expect(document.css("[data-graph-date]").size).to eq(5)
    expect(graph_day(monday + 5)).to be_nil
    expect(graph_day(monday + 6)).to be_nil
    expect(document.css("svg circle, svg path")).to be_empty
    expect(graph_metric).to eq("overall")
    expect(document.at_css(%(a[data-metric="#{virtue.id}"]))).to be_nil
  end

  it "allows next-week navigation from a past week and preserves the metric both ways" do
    sign_in_student
    get student_growth_path, params: { tab: "weekly", metric: virtues[0].id }

    get document.at_css('[data-week-navigation="previous"]')["href"]

    expect(graph_metric).to eq(virtues[0].id.to_s)
    expect(document.at_css("[data-week-start]")["data-week-start"]).to eq("2026-08-31")

    get document.at_css('[data-week-navigation="next"]')["href"]

    expect(graph_metric).to eq(virtues[0].id.to_s)
    expect(document.at_css("[data-week-start]")["data-week-start"]).to eq("2026-09-07")
    expect(document.at_css('a[data-week-navigation="next"]')).to be_nil
  end

  it "does not offer future navigation or accept a positive offset" do
    sign_in_student

    get student_growth_path, params: { tab: "weekly", week_offset: 1 }

    expect(document.at_css("[data-week-start]")["data-week-start"]).to eq("2026-09-07")
    expect(document.at_css('a[data-week-navigation="next"]')).to be_nil
  end

  it "falls back to the current week for a malformed offset" do
    sign_in_student

    get student_growth_path, params: { tab: "weekly", week_offset: "invalid" }

    expect(document.at_css("[data-week-start]")["data-week-start"]).to eq("2026-09-07")
  end

  it "offers current active virtues and retains the week when selecting a metric" do
    sign_in_student
    get student_growth_path, params: { tab: "weekly", week_offset: -1 }

    virtues.each do |virtue|
      expect(document.at_css(%(a[data-metric="#{virtue.id}"])).text).to eq(virtue.name)
    end

    get document.at_css(%(a[data-metric="#{virtues[0].id}"]))["href"]

    expect(graph_metric).to eq(virtues[0].id.to_s)
    expect(document.at_css("[data-week-start]")["data-week-start"]).to eq("2026-08-31")
  end

  it "offers and displays an inactive virtue only in a week with the Student's scores" do
    virtue = virtues[0]
    create_record(date: monday - 3, scores: { virtue => 4 })
    virtue.update!(active: false)
    sign_in_student

    get student_growth_path, params: { tab: "weekly", week_offset: -1, metric: virtue.id }

    expect(document.at_css(%(a[data-metric="#{virtue.id}"])).text).to eq(virtue.name)
    expect(graph_metric).to eq(virtue.id.to_s)
    expect(graph_day(monday - 3)["data-growth-value"]).to eq("4")

    get student_growth_path, params: { tab: "weekly", metric: virtue.id }

    expect(document.at_css(%(a[data-metric="#{virtue.id}"]))).to be_nil
    expect(graph_metric).to eq("overall")
  end

  it "does not offer an inactive virtue scored only by another Student" do
    virtue = virtues[0]
    other_student = create(:student, classroom:)
    create_record(date: monday, scores: { virtue => 5 }, owner: other_student)
    virtue.update!(active: false)
    sign_in_student

    get student_growth_path, params: { tab: "weekly", metric: virtue.id }

    expect(document.at_css(%(a[data-metric="#{virtue.id}"]))).to be_nil
    expect(graph_metric).to eq("overall")
  end

  it "falls back to overall for another Classroom's virtue" do
    unrelated_virtue = create(:classroom).virtues.first
    sign_in_student

    get student_growth_path, params: { tab: "weekly", metric: unrelated_virtue.id }

    expect(graph_metric).to eq("overall")
    expect(document.at_css(%(a[data-metric="#{unrelated_virtue.id}"]))).to be_nil
  end

  it "falls back to overall for an unknown metric" do
    sign_in_student

    get student_growth_path, params: { tab: "weekly", metric: "unknown" }

    expect(graph_metric).to eq("overall")
  end

  it "uses a fixed product color outside the Virtue palette for the overall line, points, and swatch" do
    create_record(date: monday, scores: { virtues[0] => 3 })
    create_record(date: monday + 1, scores: { virtues[0] => 4 })
    sign_in_student

    get student_growth_path, params: { tab: "weekly" }

    overall_color = StudentGrowthHelper::OVERALL_GROWTH_COLOR
    expect(Virtue::COLORS.values).not_to include(overall_color)
    expect(document.at_css("svg path")["stroke"]).to eq(overall_color)
    expect(document.css("svg circle").map { |point| point["fill"] }).to eq([overall_color] * 2)
    expect(document.at_css('[data-metric="overall"] [data-metric-swatch]')["style"])
      .to eq("background-color: #{overall_color}")
  end

  it "uses the selected virtue's stored color for its line, points, and metric swatch" do
    virtue = virtues[0]
    virtue.update!(color_key: "rose")
    create_record(date: monday, scores: { virtue => 3 })
    create_record(date: monday + 1, scores: { virtue => 4 })
    sign_in_student

    get student_growth_path, params: { tab: "weekly", metric: virtue.id }

    expect(document.at_css("svg path")["stroke"]).to eq(virtue.color_hex)
    expect(document.css("svg circle").map { |point| point["fill"] }).to eq([virtue.color_hex] * 2)
    expect(document.at_css(%([data-metric="#{virtue.id}"] [data-metric-swatch]))["style"])
      .to eq("background-color: #{virtue.color_hex}")
  end

  it "uses the current stored color for historical scores after the virtue is retired" do
    virtue = virtues[0]
    create_record(date: monday - 4, scores: { virtue => 3 })
    create_record(date: monday - 3, scores: { virtue => 4 })
    virtue.update!(color_key: "teal")
    virtue.update!(active: false)
    sign_in_student

    get student_growth_path, params: { tab: "weekly", week_offset: -1, metric: virtue.id }

    expect(document.at_css("svg path")["stroke"]).to eq(virtue.color_hex)
    expect(document.css("svg circle").map { |point| point["fill"] }).to eq([virtue.color_hex] * 2)
    expect(document.at_css(%([data-metric="#{virtue.id}"] [data-metric-swatch]))["style"])
      .to eq("background-color: #{virtue.color_hex}")
  end

  it "links the shared growth navigation and marks only the current screen active" do
    sign_in_student
    get student_growth_path

    daily_nav = document.at_css("[data-growth-dashboard-navigation]")
    expect(daily_nav.at_css('[data-growth-tab="growth"]')["aria-current"]).to eq("page")
    expect(daily_nav.at_css('[data-growth-tab="weekly"]')["aria-current"]).to be_nil

    get daily_nav.at_css('[data-growth-tab="weekly"]')["href"]

    weekly_nav = document.at_css("[data-growth-dashboard-navigation]")
    expect(weekly_nav.at_css('[data-growth-tab="weekly"]')["aria-current"]).to eq("page")
    expect(weekly_nav.at_css('[data-growth-tab="growth"]')["aria-current"]).to be_nil

    monthly = weekly_nav.at_css('[data-growth-tab="monthly"]')
    expect(monthly["aria-disabled"]).to eq("true")
    expect(monthly.text).to include(I18n.t("student_app.navigation.monthly"))
  end
end
