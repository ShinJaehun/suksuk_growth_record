require 'rails_helper'

RSpec.describe 'Admin school managers', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:school) { create(:school) }
  let(:teacher) do
    create(:user, :teacher, :active_annual_teacher,
           annual_school: school, annual_grade: 4)
  end

  it 'designates the annual teacher role' do
    sign_in admin
    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_manager
  end

  it 'promotes a member without changing assignments' do
    classroom = create(:classroom, annual_school: school, grade: 4)
    assign_teacher(classroom, teacher)
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(teacher.reload).to be_school_manager
    expect(classroom.reload.teacher).to eq(teacher)
  end

  it 'rejects promoting an inactive member without changing managers' do
    existing_manager = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school, annual_school_role: 'manager')
    inactive_teacher = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school, active: false)
    sign_in admin

    expect do
      post admin_school_school_managers_path(school), params: { user_id: inactive_teacher.id }
    end.not_to(change { school.school_years.active.first.users.where(school_role: 'manager').count })

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(edit_school_path(school))
    expect(flash[:alert]).to include(I18n.t('admin.school_managers.errors.inactive_manager'))
    expect(inactive_teacher.reload).to be_school_member
    expect(existing_manager.reload).to be_school_manager
  end

  it 'demotes a manager without changing assignments' do
    teacher.update!(school_role: 'manager')
    classroom = create(:classroom, annual_school: school, grade: 4)
    assign_teacher(classroom, teacher)
    sign_in admin

    delete admin_school_manager_path(school, teacher)

    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_member
    expect(classroom.reload.teacher).to eq(teacher)
  end

  it 'atomically replaces the existing manager' do
    existing_manager = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school, annual_school_role: 'manager')
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(edit_school_path(school))
    expect(existing_manager.reload).to be_school_member
    expect(teacher.reload).to be_school_manager
    expect(school.school_years.active.first.users.where(school_role: 'manager').count).to eq(1)
  end

  it 'succeeds without changing an existing target manager' do
    teacher.update!(school_role: 'manager')
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_manager
    expect(school.school_years.active.first.users.where(school_role: 'manager').count).to eq(1)
  end

  it 'rolls back the existing manager demotion when promotion fails' do
    existing_manager = create(:user, :teacher, :active_annual_teacher,
                              annual_school: school, annual_school_role: 'manager')
    allow_any_instance_of(User).to receive(:update!).and_wrap_original do |method, attributes|
      raise ActiveRecord::RecordInvalid if attributes[:school_role] == 'manager'

      method.call(attributes)
    end
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(existing_manager.reload).to be_school_manager
    expect(teacher.reload).to be_school_member
  end

  it 'returns to school settings after a Turbo manager change' do
    sign_in admin
    post admin_school_school_managers_path(school), params: { user_id: teacher.id },
                                                    headers: { 'Accept' => Mime[:turbo_stream].to_s }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(edit_school_path(school))
    expect(teacher.reload).to be_school_manager
  end

  it 'rejects a school manager actor' do
    actor = create(:user, :teacher, :active_annual_teacher,
                   annual_school: school, annual_school_role: 'manager')
    sign_in actor

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(root_path)
    expect(teacher.reload).to be_school_member
  end

  it 'rejects a school member actor' do
    actor = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in actor

    post admin_school_school_managers_path(school), params: { user_id: teacher.id }

    expect(response).to redirect_to(root_path)
    expect(teacher.reload).to be_school_member
  end

  it 'rejects a school manager actor demoting a manager' do
    teacher.update!(school_role: 'manager')
    actor = create(:user, :teacher, :active_annual_teacher,
                   annual_school: create(:school), annual_school_role: 'manager')
    sign_in actor

    delete admin_school_manager_path(school, teacher)

    expect(response).to redirect_to(root_path)
    expect(teacher.reload).to be_school_manager
  end

  it 'rejects a school member actor demoting a manager' do
    teacher.update!(school_role: 'manager')
    actor = create(:user, :teacher, :active_annual_teacher, annual_school: school)
    sign_in actor

    delete admin_school_manager_path(school, teacher)

    expect(response).to redirect_to(root_path)
    expect(teacher.reload).to be_school_manager
  end

  it 'rejects a non-teacher target' do
    target = create(:user, :admin)
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: target.id }

    expect(response).to have_http_status(:not_found)
  end

  it 'rejects an other-school teacher target without changing annual authority' do
    target = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))
    original_school_year = target.school_year
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: target.id }

    expect(response).to have_http_status(:not_found)
    expect(target.reload).to have_attributes(
      school_year: original_school_year,
      school_role: 'member'
    )
  end

  it 'rejects a teacher from another SchoolYear' do
    planning_year = create(:school_year, school: school, year: 2027)
    target = create(:user, :teacher, school_year: planning_year,
                                     login_id: 'planning-manager', school_role: 'member')
    sign_in admin

    post admin_school_school_managers_path(school), params: { user_id: target.id }

    expect(response).to have_http_status(:not_found)
    expect(target.reload).to be_school_member
  end
end
