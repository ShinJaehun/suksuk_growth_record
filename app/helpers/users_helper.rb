module UsersHelper
  AVATAR_ASSET_DIR = Rails.root.join("app/assets/images/avatars")
  DEFAULT_AVATAR_KEY = "boy01"
  AVAILABLE_AVATAR_KEYS = Dir.children(AVATAR_ASSET_DIR)
                             .grep(/\A.+\.png\z/)
                             .map { |filename| File.basename(filename, ".png") }
                             .freeze

  def display_name(user)
    user.name.present? ? user.name : "이름 없음"
  end

  def user_avatar_path(user, size:)
    avatar_key = user.avatar_key if available_avatar_key_for?(user, user.avatar_key)
    "avatars/#{avatar_key.presence || existing_fallback_avatar_key(user)}.png"
  end

  def fallback_avatar_key(user)
    return "admin" if user.admin?
    return "teacherM01" if user.teacher?
    "boy01"
  end

  def existing_fallback_avatar_key(user)
    fallback_key = fallback_avatar_key(user)
    return fallback_key if avatar_asset_key?(fallback_key)

    role_fallback_key = User.avatar_keys_for_role(user.role).find { |avatar_key| avatar_asset_key?(avatar_key) }
    return role_fallback_key if role_fallback_key

    available_avatar_keys.include?(DEFAULT_AVATAR_KEY) ? DEFAULT_AVATAR_KEY : available_avatar_keys.first
  end

  def user_avatar_image(user, size:, **options)
    image_tag(user_avatar_path(user, size: size), **options)
  end

  def student_avatar_path(student)
    avatar_key = student.avatar_key if Student::AVATAR_KEYS.include?(student.avatar_key) &&
      avatar_asset_key?(student.avatar_key)
    "avatars/#{avatar_key.presence || DEFAULT_AVATAR_KEY}.png"
  end

  def student_avatar_image(student, **options)
    image_tag(student_avatar_path(student), **options)
  end

  def available_avatar_key_for?(user, avatar_key)
    User.avatar_keys_for_role(user.role).include?(avatar_key) && avatar_asset_key?(avatar_key)
  end

  def avatar_asset_key?(avatar_key)
    available_avatar_keys.include?(avatar_key)
  end

  def available_avatar_keys
    AVAILABLE_AVATAR_KEYS
  end
end
