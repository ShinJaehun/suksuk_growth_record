# frozen_string_literal: true

# 개발 및 테스트 환경용 기본 데이터
#
# 새 데이터베이스:
#   bin/rails db:setup
#
# 기존 데이터베이스:
#   bin/rails db:seed
#
# 여러 번 실행해도 같은 기본 데이터를 재사용하도록 작성한다.

unless Rails.env.development? || Rails.env.test?
  puts 'Demo seeds are only available in development and test environments.'
  return
end

demo_password = 'password'
demo_student_pin = '1234'

def existing_seed_avatar_keys(keys)
  keys.select do |key|
    Rails.root.join("app/assets/images/avatars/#{key}.png").exist?
  end
end

def first_seed_avatar_key(gender, fallback)
  existing_seed_avatar_keys(User.avatar_keys_for(gender)).first || fallback
end

def seed_student_avatar_key(gender, index)
  available_keys = existing_seed_avatar_keys(User.avatar_keys_for(gender))
  return if available_keys.empty?

  available_keys[index % available_keys.length]
end

def seed_account!(
  email:,
  name:,
  role:,
  password:,
  gender: nil,
  avatar_key: nil
)
  user = User.find_or_initialize_by(email: email)

  user.assign_attributes(
    name: name,
    role: role,
    gender: gender,
    avatar_key: avatar_key,
    password: password,
    password_confirmation: password
  )

  user.save!
  user
end

def seed_student!(
  name:,
  gender:,
  avatar_key:,
  student_pin:
)
  student = User
            .where(role: 'student', name: name)
            .first_or_initialize

  student.assign_attributes(
    name: name,
    role: 'student',
    gender: gender,
    avatar_key: avatar_key,
    student_pin: student_pin
  )

  student.save!
  student
end

def seed_classroom_membership!(
  user:,
  classroom:,
  role:,
  student_number: nil
)
  membership = ClassroomMembership.find_or_initialize_by(
    user: user,
    classroom: classroom
  )

  membership.assign_attributes(
    role: role,
    status: 'active',
    student_number: student_number
  )

  membership.save!
  membership
end

def seed_students!(
  classroom:,
  count:,
  name_prefix:,
  student_pin:
)
  gender_indexes = {
    'boy' => 0,
    'girl' => 0
  }

  count.times.map do |index|
    gender = index.even? ? 'boy' : 'girl'
    avatar_index = gender_indexes.fetch(gender)
    gender_indexes[gender] += 1

    student = seed_student!(
      name: "#{name_prefix} 학생 #{format('%02d', index + 1)}",
      gender: gender,
      avatar_key: seed_student_avatar_key(gender, avatar_index),
      student_pin: student_pin
    )

    # 학생은 동시에 하나의 활성 교실에만 소속될 수 있다.
    ClassroomMembership
      .where(
        user: student,
        role: 'student',
        status: 'active'
      )
      .where.not(classroom: classroom)
      .update_all(
        status: 'inactive',
        updated_at: Time.current
      )

    seed_classroom_membership!(
      user: student,
      classroom: classroom,
      role: 'student',
      student_number: index + 1
    )

    student
  end
end

puts '== 관리자 계정 생성 =='

seed_account!(
  email: 'a@a',
  name: '개발 관리자',
  role: 'admin',
  password: demo_password,
  avatar_key: 'admin'
)

puts '== 교사 계정 생성 =='

school_manager = seed_account!(
  email: 'manager@example.com',
  name: '학교 관리자 교사',
  role: 'teacher',
  password: demo_password,
  gender: 'male',
  avatar_key: first_seed_avatar_key(
    'male',
    'teacherM01'
  )
)

classroom_teacher = seed_account!(
  email: 'teacher@example.com',
  name: '4학년 1반 담임',
  role: 'teacher',
  password: demo_password,
  gender: 'female',
  avatar_key: first_seed_avatar_key(
    'female',
    'teacherF01'
  )
)

puts '== 학교 생성 =='

school = School.find_or_initialize_by(
  name: '쑥쑥초등학교'
)

school.save!

puts '== 학교 교사 소속 생성 =='

manager_school_membership =
  SchoolMembership.find_or_initialize_by(
    user: school_manager
  )

manager_school_membership.assign_attributes(
  school: school,
  role: 'manager',
  grade: 4
)

manager_school_membership.save!

teacher_school_membership =
  SchoolMembership.find_or_initialize_by(
    user: classroom_teacher
  )

teacher_school_membership.assign_attributes(
  school: school,
  role: 'member',
  grade: 4
)

teacher_school_membership.save!

puts '== 교실 생성 =='

classroom = Classroom.find_or_initialize_by(
  school: school,
  grade: 4,
  name: '1반'
)

classroom.save!

empty_classroom = Classroom.find_or_initialize_by(
  school: school,
  grade: 4,
  name: '2반'
)

empty_classroom.save!

puts '== 교실 담당 교사 배정 =='

classroom.update!(teacher: classroom_teacher)
empty_classroom.update!(teacher: school_manager)

puts '== 학생 25명 생성 =='

students = seed_students!(
  classroom: classroom,
  count: 25,
  name_prefix: '4-1',
  student_pin: demo_student_pin
)

puts
puts '========================================'
puts 'Seed 데이터 생성 완료'
puts '========================================'
puts
puts '관리자'
puts '  이메일: a@a'
puts "  비밀번호: #{demo_password}"
puts
puts '학교 관리자 교사'
puts '  이메일: manager@example.com'
puts "  비밀번호: #{demo_password}"
puts
puts '담임 교사'
puts '  이메일: teacher@example.com'
puts "  비밀번호: #{demo_password}"
puts
puts '학생'
puts "  학교: #{school.name}"
puts "  교실: #{classroom.grade}학년 #{classroom.name}"
puts "  인원: #{students.count}명"
puts "  PIN: #{demo_student_pin}"
puts
puts '학생 로그인 토큰'
puts "  #{classroom.student_login_token}"
puts
