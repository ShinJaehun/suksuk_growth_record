require 'rails_helper'

RSpec.describe 'Classroom virtue management', type: :request do
  let(:classroom) { create(:classroom) }
  let(:teacher) do
    create(:user, :teacher, :active_annual_teacher,
           annual_school: classroom.school_year.school, annual_grade: classroom.grade)
  end
  let(:virtue) { classroom.virtues.in_display_order.first }

  before do
    assign_teacher(classroom, teacher)
    sign_in teacher
  end

  def document
    Nokogiri::HTML(response.body)
  end

  it 'shows the current homeroom teacher the management page and classroom entry point' do
    get classroom_path(classroom)
    expect(document.at_css(%(a[href="#{classroom_virtues_path(classroom)}"]))).to be_present

    get classroom_virtues_path(classroom)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('덕목 관리', '3 / 5')
    classroom.virtues.each { |item| expect(response.body).to include(item.name) }
  end

  it 'requires a signed-in teacher' do
    sign_out teacher

    get classroom_virtues_path(classroom)

    expect(response).to redirect_to(new_user_session_path)
  end

  it 'blocks another teacher from reading or creating virtues' do
    outsider = create(:user, :teacher, :active_annual_teacher,
                      annual_school: classroom.school_year.school)
    sign_out teacher
    sign_in outsider

    get classroom_virtues_path(classroom)
    expect(response).to have_http_status(:not_found)

    sign_in outsider
    expect do
      post classroom_virtues_path(classroom), params: { virtue: { name: '배려' } }
    end.not_to change(Virtue, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'allows the same-SchoolYear manager to use every virtue management action and entry point' do
    manager = create(:user, :teacher, :active_annual_teacher,
                     annual_school: classroom.school_year.school, annual_school_role: 'manager')
    sign_out teacher
    sign_in manager

    get classroom_path(classroom)
    expect(document.at_css(%(a[href="#{classroom_virtues_path(classroom)}"]))).to be_present
    get classroom_virtues_path(classroom)
    expect(response).to have_http_status(:ok)

    post classroom_virtues_path(classroom), params: { virtue: { name: '배려' } }
    created = classroom.virtues.find_by!(name: '배려')
    expect(response).to redirect_to(classroom_virtues_path(classroom))

    patch classroom_virtue_path(classroom, created), params: { virtue: { name: '서로 배려' } }
    expect(response).to redirect_to(classroom_virtues_path(classroom))
    expect(created.reload.name).to eq('서로 배려')

    patch deactivate_classroom_virtue_path(classroom, created)
    expect(response).to redirect_to(classroom_virtues_path(classroom))
    expect(created.reload).not_to be_active
  end

  it 'allows a global admin to use every virtue management action and entry point' do
    sign_out teacher
    sign_in create(:user, :admin)

    get classroom_path(classroom)
    expect(document.at_css(%(a[href="#{classroom_virtues_path(classroom)}"]))).to be_present
    get classroom_virtues_path(classroom)
    expect(response).to have_http_status(:ok)

    post classroom_virtues_path(classroom), params: { virtue: { name: '배려' } }
    created = classroom.virtues.find_by!(name: '배려')
    expect(response).to redirect_to(classroom_virtues_path(classroom))

    patch classroom_virtue_path(classroom, created), params: { virtue: { name: '서로 배려' } }
    expect(response).to redirect_to(classroom_virtues_path(classroom))
    expect(created.reload.name).to eq('서로 배려')

    patch deactivate_classroom_virtue_path(classroom, created)
    expect(response).to redirect_to(classroom_virtues_path(classroom))
    expect(created.reload).not_to be_active
  end

  it 'blocks a school manager outside the Classroom SchoolYear' do
    manager = create(:user, :teacher, :active_annual_teacher,
                     annual_school: create(:school), annual_school_role: 'manager')
    sign_out teacher
    sign_in manager

    get classroom_virtues_path(classroom)
    expect(response).to have_http_status(:not_found)

    sign_in manager
    expect do
      post classroom_virtues_path(classroom), params: { virtue: { name: '배려' } }
    end.not_to change(Virtue, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'blocks a Student session' do
    student = create(:student, classroom:, student_pin: '1234')
    sign_out teacher
    post public_student_login_path(student_login_token: classroom.student_login_token), params: {
      student_id: student.id, student_pin: '1234'
    }

    get classroom_virtues_path(classroom)
    expect(response).to redirect_to(new_user_session_path)

    expect do
      post classroom_virtues_path(classroom), params: { virtue: { name: '배려' } }
    end.not_to change(Virtue, :count)
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'blocks a former homeroom teacher' do
    classroom.current_homeroom_assignment.update!(ended_on: Date.current)

    get classroom_virtues_path(classroom)

    expect(response).to have_http_status(:not_found)
  end

  it 'blocks management of an inactive classroom' do
    classroom.update!(active: false)

    get classroom_virtues_path(classroom)

    expect(response).to have_http_status(:not_found)
  end

  it 'creates a virtue with an unused automatic color and appends its display position' do
    used_colors = classroom.virtues.active.pluck(:color_key)

    expect do
      post classroom_virtues_path(classroom), params: { virtue: { name: '배려' } }
    end.to change { classroom.virtues.count }.by(1)

    expect(response).to redirect_to(classroom_virtues_path(classroom))
    created = classroom.virtues.find_by!(name: '배려')
    expect(created).to have_attributes(active: true, position: 4)
    expect(Virtue::COLORS).to have_key(created.color_key)
    expect(used_colors).not_to include(created.color_key)
  end

  it 'automatically assigns a color when the form submits a blank choice' do
    used_colors = classroom.virtues.active.pluck(:color_key)

    post classroom_virtues_path(classroom), params: { virtue: { name: '배려', color_key: '' } }

    expect(response).to redirect_to(classroom_virtues_path(classroom))
    created = classroom.virtues.find_by!(name: '배려')
    expect(Virtue::COLORS).to have_key(created.color_key)
    expect(used_colors).not_to include(created.color_key)
  end

  it 'keeps an explicit color while ignoring identity, state, and position parameters' do
    other_classroom = create(:classroom)

    post classroom_virtues_path(classroom), params: {
      virtue: { name: '배려', color_key: 'orange', classroom_id: other_classroom.id,
                active: false, position: 99 }
    }

    expect(response).to redirect_to(classroom_virtues_path(classroom))
    expect(classroom.virtues.find_by!(name: '배려'))
      .to have_attributes(color_key: 'orange', active: true, position: 4)
    expect(other_classroom.virtues.find_by(name: '배려')).to be_nil
  end

  it 'does not offer colors used by other active virtues' do
    get classroom_virtues_path(classroom)

    create_form = document.at_css(%(form[action="#{classroom_virtues_path(classroom)}"]))
    used_colors = classroom.virtues.active.pluck(:color_key)
    offered_create_colors = create_form.css('select[name="virtue[color_key]"] option').map { |option| option['value'] }
    expect(offered_create_colors & used_colors).to be_empty

    edit_form = document.at_css(%(form[action="#{classroom_virtue_path(classroom, virtue)}"]))
    offered_edit_colors = edit_form.css('select[name="virtue[color_key]"] option').map { |option| option['value'] }
    expect(offered_edit_colors).to include(virtue.color_key)
    expect(offered_edit_colors & (used_colors - [virtue.color_key])).to be_empty
  end

  it 'rejects a duplicate active color on direct create' do
    duplicate_color = virtue.color_key

    expect do
      post classroom_virtues_path(classroom), params: { virtue: { name: '배려', color_key: duplicate_color } }
    end.not_to change(Virtue, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css('[role="alert"]').text).to include('이미 사용')
  end

  it "rejects changing an active virtue to another active virtue's color" do
    other = classroom.virtues.active.where.not(id: virtue.id).first
    original_color = virtue.color_key

    patch classroom_virtue_path(classroom, virtue), params: {
      virtue: { name: virtue.name, color_key: other.color_key }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css('[role="alert"]').text).to include('이미 사용')
    expect(virtue.reload.color_key).to eq(original_color)
  end

  it 'updates the name and color without changing the display position' do
    patch classroom_virtue_path(classroom, virtue), params: {
      virtue: { name: '책 읽기', color_key: 'rose', position: 99 }
    }

    expect(response).to redirect_to(classroom_virtues_path(classroom))
    expect(virtue.reload).to have_attributes(name: '책 읽기', color_key: 'rose', position: 1)
  end

  it 'retires a virtue and shows it read-only with its stored color' do
    original_color = virtue.color_key

    patch deactivate_classroom_virtue_path(classroom, virtue)

    expect(response).to redirect_to(classroom_virtues_path(classroom))
    expect(virtue.reload).to have_attributes(active: false, color_key: original_color)
    follow_redirect!
    inactive_section = document.at_css('[data-inactive-virtues]')
    expect(inactive_section.text).to include(virtue.name)
    expect(inactive_section.css('form, input, button')).to be_empty
    expect(inactive_section.at_css('span[style]')['style']).to eq("background-color: #{virtue.color_hex}")

    patch classroom_virtue_path(classroom, virtue), params: {
      virtue: { name: '다시 사용', color_key: 'orange', active: true }
    }
    expect(response).to have_http_status(:not_found)
    expect(virtue.reload).to have_attributes(name: '독서', active: false, color_key: original_color)
  end

  it 'hides and rejects retirement of the last active virtue' do
    classroom.virtues.where.not(id: virtue.id).update_all(active: false)
    get classroom_virtues_path(classroom)
    expect(document.at_css(%(form[action="#{deactivate_classroom_virtue_path(classroom, virtue)}"]))).to be_nil
    expect(response.body).to include(I18n.t('virtues.last_active'))

    patch deactivate_classroom_virtue_path(classroom, virtue)

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css('[role="alert"]').text).to include('마지막 덕목')
    expect(virtue.reload).to be_active
    expect(classroom.virtues.active.count).to eq(1)
  end

  it 'hides the add form at five and rejects direct requests for a sixth active virtue' do
    create(:virtue, classroom:)
    create(:virtue, classroom:)
    get classroom_virtues_path(classroom)
    expect(document.at_css(%(form[action="#{classroom_virtues_path(classroom)}"]))).to be_nil
    expect(response.body).to include(I18n.t('virtues.maximum_active'))

    expect do
      post classroom_virtues_path(classroom), params: { virtue: { name: '여섯째', color_key: 'rose' } }
    end.not_to change(Virtue, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css('[role="alert"]').text).to include('최대 5개')
    expect(classroom.virtues.active.count).to eq(5)
  end

  it 'renders a blank name error without creating a partial virtue' do
    expect do
      post classroom_virtues_path(classroom), params: { virtue: { name: '', color_key: 'rose' } }
    end.not_to change(Virtue, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css('[role="alert"]').text).to include('이름')
    expect(document.at_css('select[name="virtue[color_key]"] option[value="rose"][selected]')).to be_present
  end

  it 'rejects arbitrary hex on create' do
    expect do
      post classroom_virtues_path(classroom), params: { virtue: { name: '배려', color_key: '#123456' } }
    end.not_to change(Virtue, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css('[role="alert"]').text).to include('제공된 목록')
  end

  it 'retains the submitted name but saves no partial changes when a color update fails' do
    original_attributes = virtue.attributes

    patch classroom_virtue_path(classroom, virtue), params: {
      virtue: { name: '수정한 이름', color_key: 'invalid' }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(document.at_css('[role="alert"]').text).to include('제공된 목록')
    expect(document.at_css('input[name="virtue[name]"][value="수정한 이름"]')).to be_present
    expect(virtue.reload.attributes).to eq(original_attributes)
  end

  it "cannot update or retire another Classroom's virtue through the authorized Classroom" do
    foreign_virtue = create(:classroom).virtues.first
    original_attributes = foreign_virtue.attributes

    patch classroom_virtue_path(classroom, foreign_virtue), params: {
      virtue: { name: '변경 시도', color_key: 'rose' }
    }
    expect(response).to have_http_status(:not_found)

    sign_in teacher

    patch deactivate_classroom_virtue_path(classroom, foreign_virtue)
    expect(response).to have_http_status(:not_found)
    expect(foreign_virtue.reload.attributes).to eq(original_attributes)
  end

  it 'preserves an existing daily record when virtues are added and retired on the same day' do
    student = create(:student, classroom:)
    record = create(:daily_growth_record, :with_score, student:)
    original_scores = record.daily_growth_scores.pluck(:id, :virtue_id, :score)
    configuration = record.daily_virtue_configuration
    original_items = configuration.items.pluck(:virtue_id, :name)
    scored_virtue = record.daily_growth_scores.first.virtue

    patch classroom_virtue_path(classroom, scored_virtue), params: { virtue: { name: '책 읽기' } }
    expect(response).to redirect_to(classroom_virtues_path(classroom))
    post classroom_virtues_path(classroom), params: { virtue: { name: '배려' } }
    expect(response).to redirect_to(classroom_virtues_path(classroom))
    patch deactivate_classroom_virtue_path(classroom, scored_virtue)
    expect(response).to redirect_to(classroom_virtues_path(classroom))

    expect(record.reload.daily_growth_scores.pluck(:id, :virtue_id, :score)).to eq(original_scores)
    expect(student.daily_growth_records.count).to eq(1)
    expect(configuration.reload.items.pluck(:virtue_id, :name)).to eq(original_items)

    later_student = create(:student, classroom:)
    scores = configuration.items.index_with { 3 }.transform_keys(&:virtue_id)
    later_record = DailyGrowthRecords::Save.call(student: later_student, scores: scores)

    expect(later_record.daily_virtue_configuration).to eq(configuration)
    expect(later_record.daily_virtue_configuration.items.pluck(:virtue_id, :name)).to eq(original_items)
  end
end
