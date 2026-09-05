require "rails_helper"

RSpec.describe "Authorization redirects", type: :request do
  let(:school) { create(:school) }
  let(:classroom) { create(:classroom, school: school) }
  let(:teacher) { create(:user, :teacher) }

  it "redirects a teacher with no remaining classrooms to the classrooms index" do
    assign_teacher(classroom, teacher)
    sign_in teacher

    get classroom_path(classroom)
    expect(response).to have_http_status(:ok)

    classroom.update!(teacher: nil)
    get classroom_path(classroom), headers: { "HTTP_REFERER" => classroom_url(classroom) }

    expect(response).to redirect_to(root_path)

    follow_redirect!

    expect(response).to redirect_to(classrooms_path)
  end

end
