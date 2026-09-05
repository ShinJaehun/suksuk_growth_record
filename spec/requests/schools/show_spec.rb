require 'rails_helper'

RSpec.describe 'School overview', type: :request do
  let(:school) { create(:school, name: '아라초등학교') }
  let(:manager) do
    user = create(:user, :teacher, :active_annual_teacher,
      annual_school: school,
      annual_school_role: "manager",
      name: '학교 관리자')
    create(:school_membership, :manager, school: school, user: user).user
  end

  it 'shows only school summary and settings entry to an admin' do
    classroom = create(:classroom, school: school, name: '상세 학급 이름')
    teacher = create(:school_membership, school: school, user: create(:user, :teacher, name: '상세 교사 이름')).user
    school_manager = manager
    sign_in create(:user, :admin)

    get school_path(school)

    document = Nokogiri::HTML(response.body)
    overview = document.at_css('turbo-frame#school_overview')
    expect(response).to have_http_status(:ok)
    expect(overview.text).to include(school.name, '소속 교실', '1개', '소속 교사', '2명', school_manager.name)
    classrooms_link = overview.at_xpath(
      ".//a[normalize-space()='#{I18n.t('schools.show.back_to_classrooms')}']"
    )
    expect(classrooms_link).to be_present
    expect(classrooms_link['href']).to eq(classrooms_path(school_id: school.id))
    expect(overview.text).to include('교실 목록으로')
    expect(overview.text).not_to include('교실 목록으로 돌아가기')
    settings_link = overview.at_css(%(a[href="#{edit_school_path(school)}"]))
    expect(settings_link).to be_present
    expect(settings_link['data-turbo-frame']).to be_nil
    expect(response.body).not_to include(classroom.name, teacher.name)
    expect(overview.at_css(%(a[href="#{new_classroom_path}"]))).to be_nil
    expect(overview.at_css(%(a[href="#{new_school_teacher_path(school)}"]))).to be_nil
  end

  it 'hides school settings from the school manager while showing the manager name' do
    school_manager = manager
    sign_in school_manager

    get school_path(school)

    overview = Nokogiri::HTML(response.body).at_css('turbo-frame#school_overview')
    expect(response).to have_http_status(:ok)
    expect(overview.text).to include(school.name, school_manager.name, '교실 목록으로')
    expect(overview.at_css(%(a[href="#{edit_school_path(school)}"]))).to be_nil
  end

  it 'hides school settings from a member teacher while showing manager names' do
    school_manager = manager
    member = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    create(:school_membership, school: school, user: member)
    sign_in member

    get school_path(school)

    overview = Nokogiri::HTML(response.body).at_css('turbo-frame#school_overview')
    expect(response).to have_http_status(:ok)
    expect(overview.text).to include(school_manager.name)
    expect(overview.at_css(%(a[href="#{edit_school_path(school)}"]))).to be_nil
  end

  it 'excludes inactive teachers and managers from the overview' do
    inactive_manager = manager
    inactive_manager.update!(active: false)
    active_teacher = create(:school_membership, school: school,
                                                user: create(:user, :teacher, name: '활성 교사')).user
    inactive_teacher = create(:school_membership, school: school,
                                                  user: create(:user, :teacher, name: '비활성 교사', active: false)).user
    sign_in create(:user, :admin)

    get school_path(school)

    overview = Nokogiri::HTML(response.body).at_css('turbo-frame#school_overview')
    expect(overview.text).to include(
      '소속 교사',
      '1명',
      '지정된 학교 관리자 없음'
    )
    expect(overview.text).not_to include('3명')
  end

  it 'keeps an inactive school readable to admins and expires its manager session' do
    school_manager = manager
    school.update!(active: false)
    sign_in create(:user, :admin)

    get school_path(school)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(school.name, '비활성')

    sign_in school_manager
    get school_path(school)
    expect(response).to redirect_to(school_teacher_login_path(school))
  end
end
