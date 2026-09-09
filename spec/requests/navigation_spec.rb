require 'rails_helper'

RSpec.describe 'Navigation', type: :request do
  def navbar
    document = Nokogiri::HTML(response.body)
    document.at_css('[data-navigation-root="navbar"]').tap do |navigation|
      expect(navigation).to be_present
    end
  end

  def navbar_links
    navbar.css('a[href]').map { |link| link['href'] }
  end

  it 'shows the sign in link to a guest' do
    get new_user_session_path

    expect(navbar.text).to include('Sign in')
    expect(navbar_links).to include(new_user_session_path)
  end

  it 'shows student navigation without teacher account or management links' do
    classroom = create(:classroom)
    student = create(
      :student,
      classroom: classroom,
      student_pin: '1234'
    )

    post public_student_login_path(
      student_login_token: classroom.student_login_token
    ), params: {
      student_id: student.id,
      student_pin: '1234'
    }

    expect(response).to redirect_to(student_growth_record_path)

    get student_growth_path

    expect(navbar_links).to include(
      student_growth_path(tab: 'growth'),
      destroy_student_session_path
    )
    expect(navbar.text).not_to include(I18n.t('navigation.my_page'))
    brand = navbar.at_css('a').tap { |link| expect(link.text).to include(I18n.t('navigation.brand')) }
    expect(brand['href']).to eq(student_growth_path(tab: 'growth'))
    identity = navbar.at_css('a[data-student-pin-link]')
    expect(identity['href']).to eq(edit_student_pin_path)
    expect(identity.text).to include(student.name)
    expect(identity.at_css('img')).to be_present
    expect(identity.ancestors('summary, details')).to be_empty
    expect(identity['class'].split).not_to include('hidden')
    mobile = navbar.at_css('[data-navigation-region="mobile"]')
    expect(mobile.at_css('summary a')).to be_nil
    expect(mobile.at_css('a[data-turbo-method="delete"]')['href']).to eq(destroy_student_session_path)
    expect(navbar_links).not_to include(
      edit_user_registration_path,
      destroy_user_session_path
    )
  end

  it 'links a teacher without classrooms to the classroom index' do
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))
    sign_in teacher

    get classrooms_path

    expect(navbar_links).to include(classrooms_path)
    expect(navbar.at_css('a')['href']).to eq(root_path)
  end

  it 'links a teacher with one classroom directly to that classroom' do
    classroom = create(:classroom)
    teacher = create(:user, :teacher, :active_annual_teacher, annual_school: classroom.school_year.school)
    assign_teacher(classroom, teacher)
    sign_in teacher

    get classrooms_path
    expect(response).to redirect_to(classroom_path(classroom))
    follow_redirect!

    expect(navbar_links).to include(classroom_path(classroom))
  end
end
